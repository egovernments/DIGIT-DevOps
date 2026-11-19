package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strconv"
	"strings"
)

// emptyKubeconfig seeds the private file that `aws eks update-kubeconfig` and
// `az aks get-credentials` merge into, so neither has to parse an empty file.
const emptyKubeconfig = "apiVersion: v1\nkind: Config\nclusters: []\ncontexts: []\ncurrent-context: \"\"\npreferences: {}\nusers: []\n"

// newKubeconfigFile creates the private kubeconfig the whole run uses and
// records it so Close removes it, even when a later write fails.
func (w *Workflow) newKubeconfigFile(content []byte) error {
	f, err := os.CreateTemp("", "one-click-kubeconfig-*") // created with mode 0600
	if err != nil {
		return fmt.Errorf("creating temporary kubeconfig: %w", err)
	}
	w.kubeconfig = f.Name()
	_, werr := f.Write(content)
	if cerr := f.Close(); werr == nil {
		werr = cerr
	}
	if werr != nil {
		return fmt.Errorf("writing temporary kubeconfig: %w", werr)
	}
	return nil
}

// fetchKubeconfig builds the kubeconfig from the cluster block of the config
// file, so the operator needs no prior kubectl setup for the cluster.
func (w *Workflow) fetchKubeconfig(ctx context.Context) error {
	switch w.cfg.Provider {
	case "k3s":
		return w.fetchK3s(ctx)
	case "eks":
		return w.fetchEKS(ctx)
	case "aks":
		return w.fetchAKS(ctx)
	}
	return fmt.Errorf("unsupported provider %q", w.cfg.Provider)
}

// fetchK3s reads /etc/rancher/k3s/k3s.yaml over SSH, the way the sandbox's
// infra README documents it. The file points at 127.0.0.1, so the server is
// rewritten to the VM's public address; k3s must have been started with
// --tls-san for that address or kubectl rejects the certificate.
func (w *Workflow) fetchK3s(ctx context.Context) error {
	k := w.cfg.K3s
	w.log.Infof("Fetching the k3s kubeconfig from %s@%s over SSH", k.SSHUser, k.Host)
	if _, err := os.Stat(k.SSHKeyFile); err != nil {
		return stepErr("preflight", "set cluster.k3s.sshKeyFile to the VM's private SSH key", fmt.Errorf("ssh key: %w", err))
	}
	// The kubeconfig holds the cluster-admin client key: it is only ever
	// captured from stdout, which CmdError never records.
	raw, err := w.run.Output(ctx, "ssh",
		"-i", k.SSHKeyFile, "-p", strconv.Itoa(k.SSHPort),
		"-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "-o", "StrictHostKeyChecking=accept-new",
		k.SSHUser+"@"+k.Host,
		"sudo -n cat /etc/rancher/k3s/k3s.yaml 2>/dev/null || cat /etc/rancher/k3s/k3s.yaml")
	if err != nil {
		return stepErr("preflight",
			fmt.Sprintf("check sshUser/sshKeyFile and that port %d on %s is open to this machine", k.SSHPort, k.Host),
			fmt.Errorf("reading k3s.yaml over SSH: %w", err))
	}
	kc, err := rewriteK3sServer(raw, fmt.Sprintf("https://%s:%d", k.Host, k.APIPort))
	if err != nil {
		return stepErr("preflight", "", err)
	}
	if err := w.newKubeconfigFile(kc); err != nil {
		return err
	}
	// k3s names its context "default"; rename it to what the operator types.
	if _, err := w.run.Output(ctx, "kubectl", "--kubeconfig", w.kubeconfig,
		"config", "rename-context", "default", w.cfg.Name); err != nil {
		return stepErr("preflight", "", fmt.Errorf("renaming the k3s context: %w", err))
	}
	return nil
}

var k3sServerLine = regexp.MustCompile(`(?m)^(\s*server:\s*)\S+\s*$`)

// rewriteK3sServer points the single cluster in a k3s.yaml at server.
func rewriteK3sServer(raw []byte, server string) ([]byte, error) {
	if n := len(k3sServerLine.FindAll(raw, -1)); n != 1 {
		return nil, fmt.Errorf("expected one cluster server in k3s.yaml, found %d", n)
	}
	return k3sServerLine.ReplaceAll(raw, []byte("${1}"+server)), nil
}

// fetchEKS writes a kubeconfig whose user runs `aws eks get-token` with the
// same profile (and role, if set), so every later kubectl call authenticates
// as that AWS identity.
func (w *Workflow) fetchEKS(ctx context.Context) error {
	e := w.cfg.EKS
	profile := func(args []string) []string {
		if e.Profile != "" {
			return append(args, "--profile", e.Profile)
		}
		return args
	}
	who, err := w.run.Output(ctx, "aws", profile([]string{"sts", "get-caller-identity", "--query", "Arn", "--output", "text"})...)
	if err != nil {
		return stepErr("preflight", "log in to AWS first (aws sso login / aws configure), or set cluster.eks.profile",
			fmt.Errorf("no valid AWS credentials: %w", err))
	}
	w.log.Infof("AWS identity: %s", strings.TrimSpace(string(who)))

	w.log.Infof("Fetching the EKS kubeconfig for %s in %s", e.Name, e.Region)
	if err := w.newKubeconfigFile([]byte(emptyKubeconfig)); err != nil {
		return err
	}
	args := []string{"eks", "update-kubeconfig", "--name", e.Name, "--region", e.Region,
		"--kubeconfig", w.kubeconfig, "--alias", w.cfg.Name}
	if e.RoleARN != "" {
		args = append(args, "--role-arn", e.RoleARN)
	}
	if _, err := w.run.Output(ctx, "aws", profile(args)...); err != nil {
		return stepErr("preflight", "this AWS identity needs eks:DescribeCluster; check the cluster name and region", err)
	}
	return nil
}

// fetchAKS writes the cluster-user kubeconfig. On clusters with Entra ID
// (AAD) login that kubeconfig runs kubelogin in device-code mode, which would
// stop the run at an interactive login; it is converted to reuse `az login`.
func (w *Workflow) fetchAKS(ctx context.Context) error {
	a := w.cfg.AKS
	who, err := w.run.Output(ctx, "az", "account", "show", "--query", "user.name", "--output", "tsv")
	if err != nil {
		return stepErr("preflight", "run `az login` first", fmt.Errorf("not logged in to Azure: %w", err))
	}
	w.log.Infof("Azure identity: %s", strings.TrimSpace(string(who)))

	w.log.Infof("Fetching the AKS kubeconfig for %s in resource group %s", a.Name, a.ResourceGroup)
	if err := w.newKubeconfigFile([]byte(emptyKubeconfig)); err != nil {
		return err
	}
	args := []string{"aks", "get-credentials", "--name", a.Name, "--resource-group", a.ResourceGroup,
		"--file", w.kubeconfig, "--context", w.cfg.Name, "--overwrite-existing"}
	if a.Subscription != "" {
		args = append(args, "--subscription", a.Subscription)
	}
	if _, err := w.run.Output(ctx, "az", args...); err != nil {
		return stepErr("preflight", "this Azure identity needs the AKS Cluster User role; check the cluster name, resource group and subscription", err)
	}

	kc, err := os.ReadFile(w.kubeconfig)
	if err != nil {
		return fmt.Errorf("reading the AKS kubeconfig: %w", err)
	}
	if !strings.Contains(string(kc), "kubelogin") {
		return nil // local accounts: the kubeconfig already holds a token
	}
	if _, err := exec.LookPath("kubelogin"); err != nil {
		return stepErr("preflight", "brew install Azure/kubelogin/kubelogin",
			fmt.Errorf("the cluster uses Entra ID login, which needs kubelogin"))
	}
	if _, err := w.run.Output(ctx, "kubelogin", "convert-kubeconfig", "-l", "azurecli", "--kubeconfig", w.kubeconfig); err != nil {
		return stepErr("preflight", "", fmt.Errorf("switching the kubeconfig to az login: %w", err))
	}
	return nil
}

// providerTool is the extra CLI the run needs to fetch the kubeconfig.
func (c *Config) providerTool() string {
	return map[string]string{"k3s": "ssh", "eks": "aws", "aks": "az"}[c.Provider]
}
