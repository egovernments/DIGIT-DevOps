package main

import (
	"errors"
	"flag"
	"fmt"
	"io"
	"path/filepath"
	"slices"
	"strings"
	"time"
)

var commands = []string{"all", "argocd", "backbone", "kong", "status"}

var providers = []string{"k3s", "eks", "aks"}

// Config is everything a run needs. Every value comes from the config file
// (configfile.go); there are no built-in defaults, so a value the file does
// not set stops the run at startup instead of being guessed.
type Config struct {
	Command    string
	ConfigFile string

	Name            string // what the operator types to confirm the cluster
	Env             string
	Branch          string
	Host            string // the domain: Kong route host and DNS name
	Namespace       string // namespace of the DIGIT services
	SecretsMethod   string // sopsAge, sopsKMS or sopsAzureKV
	AgeKey          string // secrets.ageKeyFile, for age
	AWSProfile      string // secrets.awsProfile, for kms
	KongAdminSvc    string
	KongLocalPort   int
	KeycloakBaseURL string
	WaitTimeout     time.Duration // argocd.timeout
	BackboneTimeout time.Duration // waitFor.timeout
	AssumeYes       bool
	SkipGitCheck    bool
	SkipKong        bool

	Provider string // k3s | eks | aks
	K3s      K3sCluster
	EKS      EKSCluster
	AKS      AKSCluster

	AppSets          []string // ApplicationSets to wait for; "{env}" is replaced by Env
	KongServices     []kongService
	IngressNamespace string
	IngressService   string
}

type K3sCluster struct {
	Host       string // public IP or DNS name of the VM
	SSHUser    string
	SSHKeyFile string
	SSHPort    int
	APIPort    int
}

type EKSCluster struct{ Name, Region, Profile, RoleARN string }

type AKSCluster struct{ Name, ResourceGroup, Subscription string }

// parseArgs reads `<command> -f <file>`. It returns flag.ErrHelp for -h.
func parseArgs(args []string, getenv func(string) string, out io.Writer) (*Config, error) {
	cfg := &Config{Command: "all"}
	if len(args) > 0 && !strings.HasPrefix(args[0], "-") {
		cfg.Command, args = args[0], args[1:]
	}

	fs := flag.NewFlagSet("one-click-deploy", flag.ContinueOnError)
	fs.SetOutput(out)
	fs.Usage = func() { printUsage(out) }
	fs.StringVar(&cfg.ConfigFile, "config", "", "")
	fs.StringVar(&cfg.ConfigFile, "f", "", "")
	if err := fs.Parse(args); err != nil {
		return nil, err
	}
	if fs.NArg() > 0 {
		return nil, fmt.Errorf("unexpected argument %q: usage is `one-click-deploy <command> -f <config file>`", fs.Arg(0))
	}
	if !slices.Contains(commands, cfg.Command) {
		return nil, fmt.Errorf("unknown command %q (want one of: %s)", cfg.Command, strings.Join(commands, ", "))
	}
	if cfg.ConfigFile == "" {
		return nil, errors.New("-f <config file> is required: every setting comes from that file. " +
			"Start from clusters/example-k3s.yaml, example-eks.yaml or example-aks.yaml")
	}
	if err := cfg.loadFile(cfg.ConfigFile, getenv("HOME")); err != nil {
		return nil, err
	}
	return cfg, nil
}

func printUsage(w io.Writer) {
	fmt.Fprint(w, `Usage: one-click-deploy <command> -f <config file>

Every setting comes from the config file; nothing has a default. Start from
clusters/example-k3s.yaml, example-eks.yaml or example-aks.yaml. A missing or
placeholder value stops the run before anything is changed.

Commands:
  all       argocd, wait for the platform, DNS check, then kong (default)
  argocd    sops-age Secret (age only), deployer (cluster-configs + Argo CD), bootstrap
  backbone  wait until the platform Applications are Synced and Healthy
  kong      configure Kong services, routes and plugins
  status    read-only: Argo CD applications, platform, DNS and Kong routes

Options:
  -f, --config <file>   the config file (required)
  -h, --help            show this help
`)
}

func expandHome(path, home string) (string, error) {
	if path != "~" && !strings.HasPrefix(path, "~/") {
		return path, nil
	}
	if home == "" {
		return "", fmt.Errorf("cannot expand %q: HOME is not set", path)
	}
	return filepath.Join(home, strings.TrimPrefix(path, "~")), nil
}
