package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"strings"
)

// deployArgoCD installs cluster-configs and Argo CD with the Go deployer, then
// applies the app-of-apps bootstrap. From there Argo CD syncs everything else
// (application appsets, backbone appset, monitoring) from origin/<branch>.
func (w *Workflow) deployArgoCD(ctx context.Context) error {
	w.log.Banner("ARGO CD DEPLOYMENT -> " + w.cfg.Env)
	for _, s := range []step{w.applyAgeSecret, w.runDeployer, w.waitArgoCD, w.checkRepoServerIdentity, w.applyBootstrap} {
		if err := s(ctx); err != nil {
			return err
		}
	}
	if out, err := w.kubectl(ctx, "-n", "argocd", "get", "applications"); err == nil {
		fmt.Fprintln(w.log.out)
		w.log.Block(string(out))
	}
	return nil
}

// applyAgeSecret creates argocd/sops-age, which argocd-repo-server mounts to
// decrypt secrets:// value files (charts/backbone-services/argo-cd/
// argo-cd-values.yaml). It must exist before the deployer installs Argo CD.
// Rendered with --dry-run and applied, so a rerun updates it in place. KMS and
// Key Vault secrets need no key in the cluster: Argo CD uses a cloud identity.
func (w *Workflow) applyAgeSecret(ctx context.Context) error {
	w.log.Step("Step 1: sops-age Secret in namespace argocd")
	if w.secretsMethod != sopsAge {
		w.log.Infof("Secrets use %s: Argo CD decrypts with its cloud identity, so no sops-age Secret is needed.", w.secretsMethod)
		return nil
	}
	const hint = "kubectl -n argocd get secret sops-age"

	ns, err := w.kubectl(ctx, "create", "namespace", "argocd", "--dry-run=client", "-o", "yaml")
	if err != nil {
		return stepErr("argocd: sops-age", hint, err)
	}
	if _, err := w.run.Input(ctx, ns, "kubectl", "apply", "-f", "-"); err != nil {
		return stepErr("argocd: sops-age", hint, fmt.Errorf("creating namespace argocd: %w", err))
	}
	// The rendered manifest contains the private key: it goes to kubectl's
	// stdin only, and CmdError never records stdout.
	secret, err := w.kubectl(ctx, "-n", "argocd", "create", "secret", "generic", "sops-age",
		"--from-file=keys.txt="+w.cfg.AgeKey, "--dry-run=client", "-o", "yaml")
	if err != nil {
		return stepErr("argocd: sops-age", hint, err)
	}
	if _, err := w.run.Input(ctx, secret, "kubectl", "apply", "-f", "-"); err != nil {
		return stepErr("argocd: sops-age", hint, fmt.Errorf("applying Secret argocd/sops-age: %w", err))
	}
	w.log.Successf("Secret argocd/sops-age is in place.")
	return nil
}

func (w *Workflow) runDeployer(ctx context.Context) error {
	w.log.Step("Step 2: cluster-configs + Argo CD via the deployer")
	dir := filepath.Join(w.repoRoot, "deploy-as-code", "deployer")
	args := []string{"run", "main.go", "deploy", "-c", "-e", w.cfg.Env, "argo-cd"}
	w.log.Cmd("cd " + dir + " && go " + strings.Join(args, " "))

	if err := w.prompt.Confirm(ctx, "Run the deployer now?"); err != nil {
		return err
	}
	if err := w.applyArgoCRDs(ctx); err != nil {
		return err
	}
	if err := w.run.Stream(ctx, dir, "go", args...); err != nil {
		return stepErr("argocd: deployer",
			"the deployer output above names the chart that failed; nothing after this step was run", err)
	}
	w.log.Successf("Deployer completed.")
	return nil
}

// argoCRDTemplates are the Argo CD CRDs. The chart has crds.install: false
// because the ApplicationSet CRD is too large for the deployer's client-side
// `kubectl apply` (last-applied annotation limit), so they are installed here
// with server-side apply. Without them argocd-server and the
// applicationset-controller crash-loop.
var argoCRDTemplates = []string{
	"templates/crds/crd-application.yaml",
	"templates/crds/crd-applicationset.yaml",
	"templates/crds/crd-project.yaml",
}

func (w *Workflow) applyArgoCRDs(ctx context.Context) error {
	const hint = "kubectl get crd applications.argoproj.io applicationsets.argoproj.io appprojects.argoproj.io"
	chart := filepath.Join(w.repoRoot, "deploy-as-code", "helm", "charts", "backbone-services", "argo-cd")
	args := []string{"template", "argocd", chart, "--set", "crds.install=true"}
	for _, t := range argoCRDTemplates {
		args = append(args, "-s", t)
	}
	w.log.Infof("Applying the Argo CD CRDs (server-side)")
	crds, err := w.run.Output(ctx, "helm", args...)
	if err != nil {
		return stepErr("argocd: CRDs", hint, fmt.Errorf("rendering the Argo CD CRDs: %w", err))
	}
	if _, err := w.run.Input(ctx, crds, "kubectl", "apply", "--server-side", "--force-conflicts", "-f", "-"); err != nil {
		return stepErr("argocd: CRDs", hint, fmt.Errorf("applying the Argo CD CRDs: %w", err))
	}
	w.log.Successf("Argo CD CRDs are in place.")
	return nil
}

func (w *Workflow) waitArgoCD(ctx context.Context) error {
	timeout := "--timeout=" + w.cfg.WaitTimeout.String()
	w.log.Step("Step 3: waiting for Argo CD to become ready (up to " + w.cfg.WaitTimeout.String() + ")")
	w.log.Infof("This usually takes 1-3 minutes; kubectl prints nothing until it is done.")
	const hint = "kubectl -n argocd get pods"

	if _, err := w.kubectl(ctx, "-n", "argocd", "wait", "--for=condition=Available", "deployment", "--all", timeout); err != nil {
		return stepErr("argocd: wait", hint, fmt.Errorf("Argo CD deployments not Available: %w", err))
	}
	out, err := w.kubectl(ctx, "-n", "argocd", "get", "statefulset", "-o", "name")
	if err != nil {
		return stepErr("argocd: wait", hint, err)
	}
	for _, sts := range splitLines(out) {
		if _, err := w.kubectl(ctx, "-n", "argocd", "rollout", "status", sts, timeout); err != nil {
			return stepErr("argocd: wait", hint, fmt.Errorf("%s did not become ready: %w", sts, err))
		}
	}
	w.log.Successf("Argo CD is ready.")
	return nil
}

// applyBootstrap applies the local bootstrap file rather than a GitHub URL:
// checkGitState has already proved the checkout equals origin, and a
// github.com/.../blob/ URL returns an HTML page, not YAML.
func (w *Workflow) applyBootstrap(ctx context.Context) error {
	w.log.Step("Step 4: apply the " + w.cfg.Env + " bootstrap (app-of-apps)")
	file := filepath.Join(w.repoRoot, "deploy-as-code", "helm", "charts", "argo-cd", "bootstrap", w.cfg.Env+"-bootstrap.yaml")
	if _, err := os.Stat(file); err != nil {
		return stepErr("argocd: bootstrap", "check --env", fmt.Errorf("bootstrap file: %w", err))
	}
	w.log.Cmd("kubectl apply -f " + file)

	if err := w.prompt.Confirm(ctx, "Apply the bootstrap now?"); err != nil {
		return err
	}
	out, err := w.kubectl(ctx, "apply", "-f", file)
	if err != nil {
		return stepErr("argocd: bootstrap", "kubectl -n argocd get applications", err)
	}
	w.log.Block(string(out))
	w.log.Successf("Bootstrap applied. Argo CD now syncs everything else from origin/%s.", w.cfg.Branch)
	return nil
}
