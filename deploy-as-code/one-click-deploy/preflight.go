package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

// preflightDeploy runs every check a deploying command needs, before anything
// in the cluster is changed.
func (w *Workflow) preflightDeploy(ctx context.Context) error {
	if err := w.checkTools(append([]string{"git", "go", "helm", "kubectl", "sops"}, w.cfg.providerTool())...); err != nil {
		return err
	}
	if err := w.locateRepo(ctx); err != nil {
		return err
	}
	if err := w.pinContext(ctx); err != nil {
		return err
	}
	if err := w.checkClusterAdmin(ctx); err != nil {
		return err
	}
	if err := w.checkGitState(ctx); err != nil {
		return err
	}
	return w.checkSecrets(ctx)
}

// preflightCluster is the subset needed by commands that only talk to the
// cluster (backbone, kong, status).
func (w *Workflow) preflightCluster(ctx context.Context) error {
	if err := w.checkTools("kubectl", w.cfg.providerTool()); err != nil {
		return err
	}
	return w.pinContext(ctx)
}

func (w *Workflow) checkTools(tools ...string) error {
	var missing []string
	for _, t := range tools {
		if t == "" {
			continue
		}
		if _, err := exec.LookPath(t); err != nil {
			missing = append(missing, t)
		}
	}
	if len(missing) > 0 {
		return stepErr("preflight", "install them first (macOS: brew install "+strings.Join(missing, " ")+")",
			fmt.Errorf("missing required tools: %s", strings.Join(missing, ", ")))
	}
	return nil
}

func (w *Workflow) locateRepo(ctx context.Context) error {
	out, err := w.run.Output(ctx, "git", "rev-parse", "--show-toplevel")
	if err != nil {
		return stepErr("preflight", "run from inside a DIGIT-DevOps checkout",
			fmt.Errorf("not inside a git checkout: %w", err))
	}
	root := strings.TrimSpace(string(out))
	if _, err := os.Stat(filepath.Join(root, "deploy-as-code", "deployer")); err != nil {
		return stepErr("preflight", "run from inside a DIGIT-DevOps checkout",
			fmt.Errorf("%s has no deploy-as-code/deployer: %w", root, err))
	}
	w.repoRoot = root
	return nil
}

// pinContext puts the target cluster into a private single-context
// kubeconfig and points every later command at it. Without this, a
// `kubectl config use-context` in another terminal mid-run would silently
// redirect the rest of the deployment to that cluster. The kubeconfig is
// fetched from the config file's cluster block (cluster.go).
func (w *Workflow) pinContext(ctx context.Context) error {
	w.log.Step("Pinning the target cluster")
	name := w.targetName()

	if err := w.fetchKubeconfig(ctx); err != nil {
		return err
	}
	w.run.Setenv("KUBECONFIG", w.kubeconfig)

	server, err := w.kubectl(ctx, "config", "view", "-o", "jsonpath={.clusters[0].cluster.server}")
	if err != nil {
		return stepErr("preflight", "", fmt.Errorf("reading the API server of %q: %w", name, err))
	}
	nodes, err := w.kubectl(ctx, "get", "nodes", "-o", "wide", "--request-timeout=20s")
	if err != nil {
		hint := "check that the cluster is running and its API port is reachable from this machine"
		if w.cfg.Provider == "k3s" {
			hint += fmt.Sprintf("; k3s must be started with --tls-san %s", w.cfg.K3s.Host)
		}
		return stepErr("preflight", hint, fmt.Errorf("cannot reach the API server at %s: %w", server, err))
	}

	w.log.Infof("Cluster: %s", w.log.Bold(name))
	w.log.Infof("Server:  %s", w.log.Bold(string(server)))
	w.log.Block(string(nodes))
	fmt.Fprintln(w.log.out)
	// Asked even with options.assumeYes; only the read-only status command skips it.
	if w.cfg.Command != "status" {
		if err := w.prompt.ConfirmAlways(ctx, fmt.Sprintf("Is %q the right cluster?", name)); err != nil {
			return err
		}
	}
	w.log.Successf("All commands in this run are pinned to %q.", name)
	return nil
}

// checkClusterAdmin makes sure the identity can do everything a deployment
// does -- namespaces, CRDs, ClusterRoles, Secrets in every namespace -- so a
// run cannot stop halfway on a permission error.
func (w *Workflow) checkClusterAdmin(ctx context.Context) error {
	w.log.Step("Checking cluster permissions")
	out, err := w.kubectl(ctx, "auth", "can-i", "*", "*", "--all-namespaces")
	if err != nil || strings.TrimSpace(string(out)) != "yes" {
		cause := fmt.Errorf("this identity is not cluster-admin")
		if err != nil {
			cause = fmt.Errorf("%w (%v)", cause, err)
		}
		return stepErr("preflight",
			"installing Argo CD and cluster-configs needs full cluster-admin; ask the cluster owner for it (EKS: an access entry with AmazonEKSClusterAdminPolicy; AKS: Azure Kubernetes Service RBAC Cluster Admin)",
			cause)
	}
	w.log.Successf("Cluster-admin access confirmed.")
	return nil
}

// targetName is what the operator types to confirm the cluster.
func (w *Workflow) targetName() string { return w.cfg.Name }

// checkGitState makes sure the checkout equals origin/<branch>: Argo CD syncs
// from origin, while the deployer and the bootstrap apply run from this
// checkout. If the two differ, the cluster ends up with a mix of both.
func (w *Workflow) checkGitState(ctx context.Context) error {
	branch := w.cfg.Branch
	w.log.Step("Checking the checkout matches origin/" + branch)
	if w.cfg.SkipGitCheck {
		w.log.Warnf("Skipping git checks (options.skipGitCheck: true in the config file).")
		return nil
	}
	git := func(args ...string) (string, error) {
		out, err := w.run.Output(ctx, "git", append([]string{"-C", w.repoRoot}, args...)...)
		return strings.TrimSpace(string(out)), err
	}

	current, err := git("rev-parse", "--abbrev-ref", "HEAD")
	if err != nil {
		return stepErr("preflight", "", err)
	}
	if current != branch {
		return stepErr("preflight", "git checkout "+branch,
			fmt.Errorf("on branch %q, expected %q", current, branch))
	}
	dirty, err := git("status", "--porcelain", "--untracked-files=no")
	if err != nil {
		return stepErr("preflight", "", err)
	}
	if dirty != "" {
		return stepErr("preflight", "commit, stash or discard them first",
			fmt.Errorf("uncommitted changes in tracked files:\n%s", indent(dirty, "    ")))
	}
	if _, err := git("fetch", "--quiet", "origin", branch); err != nil {
		return stepErr("preflight", "check network access to github.com", err)
	}
	local, err := git("rev-parse", "HEAD")
	if err != nil {
		return stepErr("preflight", "", err)
	}
	remote, err := git("rev-parse", "origin/"+branch)
	if err != nil {
		return stepErr("preflight", "", err)
	}
	if local != remote {
		return stepErr("preflight", "git pull",
			fmt.Errorf("local %s (%s) differs from origin/%s (%s)", branch, short(local), branch, short(remote)))
	}
	w.log.Successf("On %s at %s, identical to origin.", branch, short(local))
	return nil
}

func short(sha string) string {
	if len(sha) > 9 {
		return sha[:9]
	}
	return sha
}
