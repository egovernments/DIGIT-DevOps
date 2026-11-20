package main

import (
	"context"
	"errors"
	"io/fs"
	"os"
)

// Workflow holds the state shared by the steps of one run.
type Workflow struct {
	cfg    *Config
	log    *Logger
	prompt *Prompter
	run    *Runner

	repoRoot      string
	kubeconfig    string       // pinned single-context kubeconfig; removed by Close
	tunnel        *portForward // Kong admin port-forward; stopped by Close
	secretsMethod string       // sopsAge, sopsKMS or sopsAzureKV; set by checkSecrets
}

func newWorkflow(cfg *Config, log *Logger) *Workflow {
	return &Workflow{
		cfg:    cfg,
		log:    log,
		prompt: newPrompter(os.Stdin, log.out, cfg.AssumeYes),
		run:    newRunner(),
	}
}

type step func(context.Context) error

// Run executes the steps of the selected command in order, stopping at the
// first error. Nothing after a failed step runs.
func (w *Workflow) Run(ctx context.Context) error {
	var steps []step
	switch w.cfg.Command {
	case "all":
		steps = []step{w.preflightDeploy, w.deployArgoCD, w.waitBackbone, w.checkDNS, w.maybeConfigureKong}
	case "argocd":
		steps = []step{w.preflightDeploy, w.deployArgoCD}
	case "backbone":
		steps = []step{w.preflightCluster, w.waitBackbone}
	case "kong":
		steps = []step{w.preflightCluster, w.configureKong}
	case "status":
		// Read-only, so preflightCluster skips the cluster confirmation.
		steps = []step{w.preflightCluster, w.showStatus}
	}
	for _, s := range steps {
		if err := ctx.Err(); err != nil {
			return err
		}
		if err := s(ctx); err != nil {
			return err
		}
	}
	return nil
}

// Close releases what the run created locally. It is safe to call more than
// once and after a failed or interrupted run.
func (w *Workflow) Close() {
	if w.tunnel != nil {
		w.tunnel.Stop()
		w.tunnel = nil
	}
	if w.kubeconfig != "" {
		if err := os.Remove(w.kubeconfig); err != nil && !errors.Is(err, fs.ErrNotExist) {
			w.log.Warnf("Could not remove temporary kubeconfig %s: %v", w.kubeconfig, err)
		}
		w.kubeconfig = ""
	}
}

func (w *Workflow) kubectl(ctx context.Context, args ...string) ([]byte, error) {
	return w.run.Output(ctx, "kubectl", args...)
}

func (w *Workflow) maybeConfigureKong(ctx context.Context) error {
	if w.cfg.SkipKong {
		w.log.Warnf("Skipping Kong (kong.enabled: false in the config file).")
		return nil
	}
	return w.configureKong(ctx)
}
