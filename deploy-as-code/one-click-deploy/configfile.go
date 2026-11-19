package main

import (
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	"gopkg.in/yaml.v3"
)

// yamlBool is a true/false field that remembers whether it was written at
// all, and keeps a <placeholder> instead of failing to decode it, so both are
// reported in the same list as every other problem.
type yamlBool struct {
	set bool
	raw string
}

func (b *yamlBool) UnmarshalYAML(n *yaml.Node) error {
	if n.Kind != yaml.ScalarNode {
		return fmt.Errorf("line %d: expected true or false", n.Line)
	}
	b.set, b.raw = true, n.Value
	return nil
}

// yamlScalar is a number field kept as written, for the same reasons as
// yamlBool.
type yamlScalar = yamlBool

// fileConfig is the layout of the config file (clusters/example-*.yaml).
// Every field the run uses must be written explicitly; booleans use yamlBool
// so that "not written" can be told apart from false.
type fileConfig struct {
	Name      string `yaml:"name"`
	Env       string `yaml:"env"`
	Branch    string `yaml:"branch"`
	Domain    string `yaml:"domain"`
	Namespace string `yaml:"namespace"`

	Cluster struct {
		Provider string `yaml:"provider"`
		K3s      *struct {
			Host       string     `yaml:"host"`
			SSHUser    string     `yaml:"sshUser"`
			SSHKeyFile string     `yaml:"sshKeyFile"`
			SSHPort    yamlScalar `yaml:"sshPort"`
			APIPort    yamlScalar `yaml:"apiPort"`
		} `yaml:"k3s"`
		EKS *struct {
			Name    string `yaml:"name"`
			Region  string `yaml:"region"`
			Profile string `yaml:"profile"`
			RoleARN string `yaml:"roleArn"` // the one optional field: only for assumed-role access
		} `yaml:"eks"`
		AKS *struct {
			Name          string `yaml:"name"`
			ResourceGroup string `yaml:"resourceGroup"`
			Subscription  string `yaml:"subscription"`
		} `yaml:"aks"`
	} `yaml:"cluster"`

	Secrets struct {
		Method     string `yaml:"method"`
		AgeKeyFile string `yaml:"ageKeyFile"`
		AWSProfile string `yaml:"awsProfile"`
	} `yaml:"secrets"`

	ArgoCD struct {
		Timeout string `yaml:"timeout"`
	} `yaml:"argocd"`

	WaitFor struct {
		AppSets []string `yaml:"appSets"`
		Timeout string   `yaml:"timeout"`
	} `yaml:"waitFor"`

	Ingress struct {
		Namespace string `yaml:"namespace"`
		Service   string `yaml:"service"`
	} `yaml:"ingress"`

	Kong struct {
		Enabled         yamlBool   `yaml:"enabled"`
		AdminService    string     `yaml:"adminService"`
		LocalPort       yamlScalar `yaml:"localPort"`
		KeycloakBaseURL string     `yaml:"keycloakBaseURL"`
		Services        []struct {
			Name       string   `yaml:"name"`
			K8sService string   `yaml:"k8sService"`
			Path       string   `yaml:"path"`
			StripPath  yamlBool `yaml:"stripPath"`
			Auth       yamlBool `yaml:"auth"`
		} `yaml:"services"`
	} `yaml:"kong"`

	Options struct {
		AssumeYes    yamlBool `yaml:"assumeYes"`
		SkipGitCheck yamlBool `yaml:"skipGitCheck"`
	} `yaml:"options"`
}

// checker collects every problem in the file, so one run reports all of them.
type checker struct{ problems []string }

func (c *checker) addf(format string, a ...any) {
	c.problems = append(c.problems, fmt.Sprintf(format, a...))
}

// isPlaceholder matches the <...> values of the example files.
func isPlaceholder(s string) bool { return strings.HasPrefix(s, "<") && strings.HasSuffix(s, ">") }

func (c *checker) str(field, v string) string {
	switch v = strings.TrimSpace(v); {
	case v == "":
		c.addf("%s is missing", field)
	case isPlaceholder(v):
		c.addf("%s is still the placeholder %s", field, v)
	}
	return v
}

func (c *checker) oneOf(field, v string, allowed []string) string {
	if v = c.str(field, v); v != "" && !isPlaceholder(v) && !slices.Contains(allowed, v) {
		c.addf("%s %q is not one of: %s", field, v, strings.Join(allowed, ", "))
	}
	return v
}

func (c *checker) port(field string, v yamlScalar) int {
	raw := strings.TrimSpace(v.raw)
	if !v.set || raw == "" {
		c.addf("%s is missing", field)
		return 0
	}
	if isPlaceholder(raw) {
		c.addf("%s is still the placeholder %s", field, raw)
		return 0
	}
	n, err := strconv.Atoi(raw)
	if err != nil || n < 1 || n > 65535 {
		c.addf("%s %q is not a valid port", field, raw)
		return 0
	}
	return n
}

func (c *checker) boolean(field string, v yamlBool) bool {
	switch raw := strings.ToLower(strings.TrimSpace(v.raw)); {
	case !v.set || raw == "":
		c.addf("%s is missing (write true or false)", field)
	case isPlaceholder(raw):
		c.addf("%s is still the placeholder %s (write true or false)", field, v.raw)
	case raw == "true":
		return true
	case raw != "false":
		c.addf("%s %q must be true or false", field, v.raw)
	}
	return false
}

func (c *checker) duration(field, v string) time.Duration {
	if v = c.str(field, v); v == "" || isPlaceholder(v) {
		return 0
	}
	d, err := time.ParseDuration(v)
	if err != nil || d <= 0 {
		c.addf("%s %q is not a positive duration such as 10m or 600s", field, v)
	}
	return d
}

// path checks a key-file path and resolves ~ and paths relative to the file.
func (c *checker) path(field, v, baseDir, home string) string {
	if v = c.str(field, v); v == "" || isPlaceholder(v) {
		return v
	}
	p, err := expandHome(v, home)
	if err != nil {
		c.addf("%s: %v", field, err)
		return v
	}
	if !filepath.IsAbs(p) {
		p = filepath.Join(baseDir, p)
	}
	return p
}

func (c *checker) unused(field string, set bool, why string) {
	if set {
		c.addf("%s must not be set: %s", field, why)
	}
}

// loadFile reads the config file into c. Unknown keys are rejected, and every
// value the run uses must be present and not a <placeholder>; all problems are
// reported together before anything runs.
func (c *Config) loadFile(path, home string) error {
	f, err := os.Open(path)
	if err != nil {
		return fmt.Errorf("config file: %w", err)
	}
	defer f.Close()

	var fc fileConfig
	dec := yaml.NewDecoder(f)
	dec.KnownFields(true)
	if err := dec.Decode(&fc); err != nil && !errors.Is(err, io.EOF) {
		return fmt.Errorf("config file %s: %w", path, err)
	}
	c.ConfigFile = path
	baseDir := filepath.Dir(path)
	var chk checker

	c.Name = chk.str("name", fc.Name)
	c.Env = chk.str("env", fc.Env)
	c.Branch = chk.str("branch", fc.Branch)
	c.Host = chk.str("domain", fc.Domain)
	c.Namespace = chk.str("namespace", fc.Namespace)

	c.Provider = chk.oneOf("cluster.provider", fc.Cluster.Provider, providers)
	cl := fc.Cluster
	for _, other := range providers {
		present := map[string]bool{"k3s": cl.K3s != nil, "eks": cl.EKS != nil, "aks": cl.AKS != nil}[other]
		if other != c.Provider && present {
			chk.addf("cluster.%s must not be set when cluster.provider is %q (remove the block)", other, c.Provider)
		}
	}
	switch c.Provider {
	case "k3s":
		if cl.K3s == nil {
			chk.addf("cluster.k3s is missing (host, sshUser, sshKeyFile, sshPort, apiPort)")
			break
		}
		c.K3s = K3sCluster{
			Host:       chk.str("cluster.k3s.host", cl.K3s.Host),
			SSHUser:    chk.str("cluster.k3s.sshUser", cl.K3s.SSHUser),
			SSHKeyFile: chk.path("cluster.k3s.sshKeyFile", cl.K3s.SSHKeyFile, baseDir, home),
			SSHPort:    chk.port("cluster.k3s.sshPort", cl.K3s.SSHPort),
			APIPort:    chk.port("cluster.k3s.apiPort", cl.K3s.APIPort),
		}
	case "eks":
		if cl.EKS == nil {
			chk.addf("cluster.eks is missing (name, region, profile)")
			break
		}
		c.EKS = EKSCluster{
			Name:    chk.str("cluster.eks.name", cl.EKS.Name),
			Region:  chk.str("cluster.eks.region", cl.EKS.Region),
			Profile: chk.str("cluster.eks.profile", cl.EKS.Profile),
			RoleARN: strings.TrimSpace(cl.EKS.RoleARN),
		}
		if isPlaceholder(c.EKS.RoleARN) {
			chk.addf("cluster.eks.roleArn is still the placeholder %s (set it, or remove the line)", c.EKS.RoleARN)
		}
	case "aks":
		if cl.AKS == nil {
			chk.addf("cluster.aks is missing (name, resourceGroup, subscription)")
			break
		}
		c.AKS = AKSCluster{
			Name:          chk.str("cluster.aks.name", cl.AKS.Name),
			ResourceGroup: chk.str("cluster.aks.resourceGroup", cl.AKS.ResourceGroup),
			Subscription:  chk.str("cluster.aks.subscription", cl.AKS.Subscription),
		}
	}

	s := fc.Secrets
	c.SecretsMethod = chk.oneOf("secrets.method", s.Method, []string{sopsAge, sopsKMS, sopsAzureKV})
	switch c.SecretsMethod {
	case sopsAge:
		c.AgeKey = chk.path("secrets.ageKeyFile", s.AgeKeyFile, baseDir, home)
		chk.unused("secrets.awsProfile", s.AWSProfile != "", "it is only used with method kms")
	case sopsKMS:
		c.AWSProfile = chk.str("secrets.awsProfile", s.AWSProfile)
		chk.unused("secrets.ageKeyFile", s.AgeKeyFile != "", "it is only used with method age")
	case sopsAzureKV:
		chk.unused("secrets.ageKeyFile", s.AgeKeyFile != "", "it is only used with method age")
		chk.unused("secrets.awsProfile", s.AWSProfile != "", "it is only used with method kms")
	}

	c.WaitTimeout = chk.duration("argocd.timeout", fc.ArgoCD.Timeout)
	c.BackboneTimeout = chk.duration("waitFor.timeout", fc.WaitFor.Timeout)
	if len(fc.WaitFor.AppSets) == 0 {
		chk.addf("waitFor.appSets is missing (the ApplicationSets to wait for)")
	}
	c.AppSets = nil
	for i, a := range fc.WaitFor.AppSets {
		c.AppSets = append(c.AppSets, chk.str(fmt.Sprintf("waitFor.appSets[%d]", i), a))
	}

	c.IngressNamespace = chk.str("ingress.namespace", fc.Ingress.Namespace)
	c.IngressService = chk.str("ingress.service", fc.Ingress.Service)

	k := fc.Kong
	kongEnabled := chk.boolean("kong.enabled", k.Enabled)
	c.SkipKong = !kongEnabled
	if kongEnabled {
		c.KongAdminSvc = chk.str("kong.adminService", k.AdminService)
		c.KongLocalPort = chk.port("kong.localPort", k.LocalPort)
		c.KeycloakBaseURL = chk.str("kong.keycloakBaseURL", k.KeycloakBaseURL)
		if len(k.Services) == 0 {
			chk.addf("kong.services is missing (the services to expose), or set kong.enabled: false")
		}
		c.KongServices = nil
		seen := map[string]bool{}
		for i, svc := range k.Services {
			f := fmt.Sprintf("kong.services[%d]", i)
			ks := kongService{
				Name:      chk.str(f+".name", svc.Name),
				K8sSvc:    chk.str(f+".k8sService", svc.K8sService),
				Path:      strings.TrimPrefix(chk.str(f+".path", svc.Path), "/"),
				StripPath: chk.boolean(f+".stripPath", svc.StripPath),
				Auth:      chk.boolean(f+".auth", svc.Auth),
			}
			if ks.Name != "" && seen[ks.Name] {
				chk.addf("%s.name %q is listed twice", f, ks.Name)
			}
			seen[ks.Name] = true
			c.KongServices = append(c.KongServices, ks)
		}
	}

	c.AssumeYes = chk.boolean("options.assumeYes", fc.Options.AssumeYes)
	c.SkipGitCheck = chk.boolean("options.skipGitCheck", fc.Options.SkipGitCheck)

	if len(chk.problems) > 0 {
		return fmt.Errorf("config file %s is not complete (%d problems):\n  - %s",
			path, len(chk.problems), strings.Join(chk.problems, "\n  - "))
	}
	return nil
}
