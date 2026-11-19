package main

import (
	"errors"
	"flag"
	"io"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"testing"
	"time"
)

// validK3s is a complete config; tests edit it to break one thing at a time.
const validK3s = `
name: sandbox
env: k3s-deployment
branch: k3s-deployment
domain: k3s-deployment.digit.org
namespace: egov
cluster:
  provider: k3s
  k3s: { host: 20.235.123.15, sshUser: azureuser, sshKeyFile: keys/ssh, sshPort: 22, apiPort: 6443 }
secrets: { method: age, ageKeyFile: ~/age.key }
argocd: { timeout: 10m }
waitFor: { appSets: [ "{env}-backbone-appset" ], timeout: 20m }
ingress: { namespace: egov, service: ingress-nginx-controller }
kong:
  enabled: true
  adminService: kong-kong-admin
  localPort: 18001
  keycloakBaseURL: http://kc
  services:
    - { name: pdf-v3, k8sService: pdf-v3, path: /pdf-v3, stripPath: false, auth: true }
options: { assumeYes: false, skipGitCheck: true }
`

func writeConfig(t *testing.T, body string) string {
	t.Helper()
	path := filepath.Join(t.TempDir(), "cfg.yaml")
	if err := os.WriteFile(path, []byte(body), 0o600); err != nil {
		t.Fatal(err)
	}
	return path
}

func load(t *testing.T, body string) (*Config, error) {
	t.Helper()
	return parseArgs([]string{"all", "-f", writeConfig(t, body)}, envFrom(map[string]string{"HOME": "/home/op"}), io.Discard)
}

func TestCompleteConfigLoads(t *testing.T) {
	cfg, err := load(t, validK3s)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.Name != "sandbox" || cfg.Host != "k3s-deployment.digit.org" || cfg.Namespace != "egov" || cfg.SecretsMethod != sopsAge {
		t.Errorf("cfg = %+v", cfg)
	}
	if want := filepath.Join(filepath.Dir(cfg.ConfigFile), "keys/ssh"); cfg.K3s.SSHKeyFile != want || cfg.K3s.APIPort != 6443 {
		t.Errorf("k3s = %+v, want key %s", cfg.K3s, want)
	}
	if cfg.AgeKey != "/home/op/age.key" || cfg.WaitTimeout != 10*time.Minute || cfg.BackboneTimeout != 20*time.Minute {
		t.Errorf("secrets/timeouts = %q %v %v", cfg.AgeKey, cfg.WaitTimeout, cfg.BackboneTimeout)
	}
	if cfg.SkipKong || cfg.AssumeYes || !cfg.SkipGitCheck || cfg.KongLocalPort != 18001 {
		t.Errorf("flags = %+v", cfg)
	}
	if len(cfg.KongServices) != 1 || cfg.KongServices[0] != (kongService{Name: "pdf-v3", K8sSvc: "pdf-v3", Path: "pdf-v3", Auth: true}) {
		t.Errorf("kong services = %+v", cfg.KongServices)
	}
	w := &Workflow{cfg: cfg}
	if got := w.backboneAppSets(); len(got) != 1 || got[0] != "k3s-deployment-backbone-appset" {
		t.Errorf("appsets = %v", got)
	}
}

// The templates must name every field: loading one may only complain about
// placeholders, never about something missing.
func TestTemplatesContainEveryField(t *testing.T) {
	for _, path := range []string{"clusters/example-k3s.yaml", "clusters/example-eks.yaml", "clusters/example-aks.yaml"} {
		t.Run(path, func(t *testing.T) {
			_, err := parseArgs([]string{"-f", path}, envFrom(map[string]string{"HOME": "/h"}), io.Discard)
			if err == nil {
				t.Fatal("a template with placeholders must not load")
			}
			for _, line := range strings.Split(err.Error(), "\n")[1:] {
				if !strings.Contains(line, "still the placeholder") {
					t.Errorf("unexpected problem: %s", line)
				}
			}
			if !strings.Contains(err.Error(), "name is still the placeholder <cluster-name>") {
				t.Errorf("err = %v", err)
			}

			// Filling in only the placeholders must give a complete config.
			raw, _ := os.ReadFile(path)
			filled := regexp.MustCompile(`<[^>]+>`).ReplaceAllString(string(raw), "x")
			if _, err := load(t, filled); err != nil {
				t.Errorf("template with placeholders filled in does not load: %v", err)
			}
		})
	}
}

func TestEmptyConfigListsEverything(t *testing.T) {
	_, err := load(t, "")
	if err == nil {
		t.Fatal("expected an error")
	}
	for _, want := range []string{
		"name is missing", "env is missing", "branch is missing", "domain is missing", "namespace is missing",
		"cluster.provider is missing", "secrets.method is missing", "argocd.timeout is missing",
		"waitFor.appSets is missing", "waitFor.timeout is missing", "ingress.namespace is missing",
		"ingress.service is missing", "kong.enabled is missing", "options.assumeYes is missing", "options.skipGitCheck is missing",
	} {
		if !strings.Contains(err.Error(), want) {
			t.Errorf("missing %q in:\n%v", want, err)
		}
	}
}

func TestConfigProblems(t *testing.T) {
	tests := map[string]struct{ from, to, want string }{
		"unknown key":          {"namespace: egov", "namespace: egov\nnamspace: x", "field namspace not found"},
		"missing k3s field":    {"sshUser: azureuser, ", "", "cluster.k3s.sshUser is missing"},
		"missing port":         {"apiPort: 6443 ", "", "cluster.k3s.apiPort is missing"},
		"bad port":             {"sshPort: 22", "sshPort: 70000", `cluster.k3s.sshPort "70000" is not a valid port`},
		"bad provider":         {"provider: k3s", "provider: gke", `cluster.provider "gke" is not one of`},
		"other provider block": {"options:", "  eks: { name: x }\noptions:", ""},
		"bad duration":         {"timeout: 10m", "timeout: soon", `argocd.timeout "soon" is not a positive duration`},
		"bad bool":             {"assumeYes: false", "assumeYes: yes-please", `options.assumeYes "yes-please" must be true or false`},
		"missing bool":         {"stripPath: false, ", "", "kong.services[0].stripPath is missing"},
		"placeholder":          {"host: 20.235.123.15", "host: <vm-public-ip>", "cluster.k3s.host is still the placeholder <vm-public-ip>"},
		"age without key":      {"ageKeyFile: ~/age.key", "ageKeyFile: ''", "secrets.ageKeyFile is missing"},
		"kms with age key":     {"method: age", "method: kms", "secrets.ageKeyFile must not be set"},
		"duplicate service":    {"auth: true }", "auth: true }\n    - { name: pdf-v3, k8sService: a, path: b, stripPath: false, auth: false }", "is listed twice"},
		"no services":          {"  services:\n    - { name: pdf-v3, k8sService: pdf-v3, path: /pdf-v3, stripPath: false, auth: true }\n", "", "kong.services is missing"},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			body := strings.Replace(validK3s, tt.from, tt.to, 1)
			if body == validK3s {
				t.Fatalf("test edit %q did not apply", tt.from)
			}
			if name == "other provider block" {
				body = strings.Replace(validK3s, "  k3s:", "  eks: { name: x }\n  k3s:", 1)
				tt.want = `cluster.eks must not be set when cluster.provider is "k3s"`
			}
			_, err := load(t, body)
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("err = %v, want it to contain %q", err, tt.want)
			}
		})
	}
}

func TestKongDisabledNeedsNoKongFields(t *testing.T) {
	start := strings.Index(validK3s, "kong:")
	end := strings.Index(validK3s, "options:")
	cfg, err := load(t, validK3s[:start]+"kong: { enabled: false }\n"+validK3s[end:])
	if err != nil {
		t.Fatal(err)
	}
	if !cfg.SkipKong {
		t.Error("SkipKong should be true")
	}
}

func TestProviderSecretsRules(t *testing.T) {
	eks := strings.Replace(validK3s,
		"  k3s: { host: 20.235.123.15, sshUser: azureuser, sshKeyFile: keys/ssh, sshPort: 22, apiPort: 6443 }",
		"  eks: { name: digit, region: ap-south-1, profile: egov }", 1)
	eks = strings.Replace(eks, "provider: k3s", "provider: eks", 1)
	eks = strings.Replace(eks, "secrets: { method: age, ageKeyFile: ~/age.key }", "secrets: { method: kms, awsProfile: egov-kms }", 1)
	cfg, err := load(t, eks)
	if err != nil {
		t.Fatal(err)
	}
	if cfg.EKS.Profile != "egov" || cfg.AWSProfile != "egov-kms" || cfg.SecretsMethod != sopsKMS || cfg.AgeKey != "" {
		t.Errorf("cfg = %+v", cfg)
	}
	_, err = load(t, strings.Replace(eks, "secrets: { method: kms, awsProfile: egov-kms }", "secrets: { method: kms }", 1))
	if err == nil || !strings.Contains(err.Error(), "secrets.awsProfile is missing") {
		t.Errorf("kms without profile: %v", err)
	}
}

func TestParseArgs(t *testing.T) {
	tests := map[string]struct {
		args []string
		want string
	}{
		"no config file":   {[]string{"all"}, "-f <config file> is required"},
		"unknown command":  {[]string{"deploy", "-f", "x"}, `unknown command "deploy"`},
		"positional after": {[]string{"-f", "x", "kong"}, "unexpected argument"},
		"removed flag":     {[]string{"all", "--context", "x"}, "flag provided but not defined"},
		"missing file":     {[]string{"all", "-f", "/does/not/exist.yaml"}, "no such file"},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			_, err := parseArgs(tt.args, envFrom(nil), io.Discard)
			if err == nil || !strings.Contains(err.Error(), tt.want) {
				t.Fatalf("err = %v, want %q", err, tt.want)
			}
		})
	}
	if _, err := parseArgs([]string{"--help"}, envFrom(nil), io.Discard); !errors.Is(err, flag.ErrHelp) {
		t.Errorf("--help: err = %v", err)
	}
}
