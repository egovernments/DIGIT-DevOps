package main

import (
	"context"
	"errors"
	"strings"
)

// showStatus is read-only and best-effort: each section reports its own
// problem and the next section still runs.
func (w *Workflow) showStatus(ctx context.Context) error {
	w.log.Banner("STATUS -> " + w.targetName())

	w.log.Step("Argo CD applications")
	if out, err := w.kubectl(ctx, "-n", "argocd", "get", "applications"); err != nil {
		w.log.Warnf("Argo CD not installed or no applications yet: %v", err)
	} else {
		w.log.Block(string(out))
	}

	w.log.Step("Backbone (" + strings.Join(w.backboneAppSets(), ", ") + ")")
	states, err := w.backboneSnapshot(ctx)
	switch {
	case errors.Is(err, errNotYet):
		w.log.Warnf("%v", err)
	case err != nil:
		w.log.Warnf("Could not read backbone status: %v", err)
	default:
		w.log.Block(formatStates(states))
	}

	if err := w.checkDNS(ctx); err != nil {
		return err
	}
	client, err := w.openKongTunnel(ctx)
	if err != nil {
		w.log.Warnf("Kong: %v", err)
		return nil
	}
	w.printKongSummary(ctx, client)
	return nil
}
