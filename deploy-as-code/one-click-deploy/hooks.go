package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"time"
)

// Recovery from a sync stuck on a hook that no longer exists.
//
// On a first install Argo CD often retries a sync (the repo-server is busy
// rendering every app at once). When the retried sync reruns a hook with
// hook-delete-policy BeforeHookCreation, Argo CD deletes the previous hook
// Job and applies the new one; with ServerSideApply the apply can land on the
// old Job while it is still being deleted, and the Job then disappears. The
// operation keeps "waiting for completion of hook batch/Job/<name>" forever.
// Seen with keycloak-db-create and ingress-nginx's admission hooks.
//
// The fix is what an operator would do by hand: terminate the stuck
// operation and start a new sync, which creates the hook again.

// A hook must be missing this long before the sync is restarted, so a hook
// that Argo CD is in the middle of recreating is left alone.
const hookMissingGrace = time.Minute

// Restarts per Application per run, so a hook that keeps vanishing for some
// other reason surfaces as a timeout instead of an endless loop.
const maxHookRestarts = 2

type hookResource struct {
	Group     string `json:"group"`
	Kind      string `json:"kind"`
	Namespace string `json:"namespace"`
	Name      string `json:"name"`
	HookType  string `json:"hookType"`
	HookPhase string `json:"hookPhase"`
}

type hookApp struct {
	Spec struct {
		Source *struct {
			TargetRevision string `json:"targetRevision"`
		} `json:"source"`
		SyncPolicy *struct {
			SyncOptions []string `json:"syncOptions"`
		} `json:"syncPolicy"`
	} `json:"spec"`
	Status struct {
		OperationState *struct {
			Phase      string `json:"phase"`
			Message    string `json:"message"`
			SyncResult *struct {
				Resources []hookResource `json:"resources"`
			} `json:"syncResult"`
		} `json:"operationState"`
	} `json:"status"`
}

// runningHooks returns the hooks a running sync is waiting on.
func runningHooks(a hookApp) []hookResource {
	op := a.Status.OperationState
	if op == nil || op.Phase != "Running" || op.SyncResult == nil ||
		!strings.Contains(op.Message, "waiting for completion of hook") {
		return nil
	}
	var hooks []hookResource
	for _, r := range op.SyncResult.Resources {
		if r.HookType != "" && r.HookPhase == "Running" && r.Kind != "" && r.Name != "" {
			hooks = append(hooks, r)
		}
	}
	return hooks
}

// kubectlRef is the resource argument for `kubectl get`, e.g. job.batch.
func (h hookResource) kubectlRef() string {
	if h.Group == "" {
		return strings.ToLower(h.Kind)
	}
	return strings.ToLower(h.Kind) + "." + h.Group
}

func (h hookResource) String() string {
	if h.Group == "" {
		return h.Kind + "/" + h.Name
	}
	return h.Group + "/" + h.Kind + "/" + h.Name
}

// syncRestartPatch is the merge patch that starts a sync, as `argocd app
// sync` would: same revision and sync options as the Application's spec.
func syncRestartPatch(a hookApp) ([]byte, error) {
	if a.Spec.Source == nil || a.Spec.Source.TargetRevision == "" {
		return nil, fmt.Errorf("application has no spec.source.targetRevision")
	}
	sync := map[string]any{"revision": a.Spec.Source.TargetRevision}
	if a.Spec.SyncPolicy != nil && len(a.Spec.SyncPolicy.SyncOptions) > 0 {
		sync["syncOptions"] = a.Spec.SyncPolicy.SyncOptions
	}
	return json.Marshal(map[string]any{"operation": map[string]any{
		"initiatedBy": map[string]any{"username": "one-click-deploy"},
		"sync":        sync,
	}})
}

// hookWatch remembers, across polls, since when each app's hook is missing
// and how often its sync was restarted.
type hookWatch struct {
	missingSince map[string]time.Time
	restarts     map[string]int
}

func newHookWatch() *hookWatch {
	return &hookWatch{missingSince: map[string]time.Time{}, restarts: map[string]int{}}
}

// recoverStuckHooks restarts the sync of any not-ready app that has been
// waiting for a missing hook for longer than hookMissingGrace. Failures are
// only logged: the wait loop and its timeout stay in charge.
func (w *Workflow) recoverStuckHooks(ctx context.Context, hw *hookWatch, states []appState) {
	for _, s := range states {
		if s.ready() || !strings.Contains(s.Detail, "waiting for completion of hook") {
			delete(hw.missingSince, s.Name)
			continue
		}
		out, err := w.kubectl(ctx, "-n", "argocd", "get", "applications.argoproj.io", s.Name, "-o", "json")
		if err != nil {
			continue
		}
		var app hookApp
		if err := json.Unmarshal(out, &app); err != nil {
			continue
		}
		var missing *hookResource
		for _, h := range runningHooks(app) {
			args := []string{"get", h.kubectlRef(), h.Name, "-o", "name"}
			if h.Namespace != "" {
				args = append([]string{"-n", h.Namespace}, args...)
			}
			if _, err := w.kubectl(ctx, args...); isNotFound(err) {
				h := h
				missing = &h
				break
			}
		}
		if missing == nil {
			delete(hw.missingSince, s.Name)
			continue
		}
		first, seen := hw.missingSince[s.Name]
		if !seen {
			hw.missingSince[s.Name] = time.Now()
			continue
		}
		if time.Since(first) < hookMissingGrace || hw.restarts[s.Name] >= maxHookRestarts {
			continue
		}
		hw.restarts[s.Name]++
		delete(hw.missingSince, s.Name)
		w.log.Warnf("%s: Argo CD is waiting for hook %s, which no longer exists. Restarting this app's sync (%d/%d).",
			s.Name, missing, hw.restarts[s.Name], maxHookRestarts)
		if err := w.restartSync(ctx, s.Name, app); err != nil {
			w.log.Warnf("%s: could not restart the sync: %v", s.Name, err)
		}
	}
}

// restartSync terminates the stuck operation and, unless auto-sync has
// already started a new one, starts a sync of the app's target revision.
func (w *Workflow) restartSync(ctx context.Context, name string, app hookApp) error {
	patch, err := syncRestartPatch(app)
	if err != nil {
		return err
	}
	if _, err := w.kubectl(ctx, "-n", "argocd", "patch", "applications.argoproj.io", name, "--type", "merge",
		"-p", `{"status":{"operationState":{"phase":"Terminating"}}}`); err != nil {
		return fmt.Errorf("terminating the operation: %w", err)
	}

	phase := "Terminating"
	deadline := time.Now().Add(time.Minute)
	for phase == "Terminating" {
		if time.Now().After(deadline) {
			return fmt.Errorf("operation still Terminating after 1m")
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-time.After(2 * time.Second):
		}
		out, err := w.kubectl(ctx, "-n", "argocd", "get", "applications.argoproj.io", name,
			"-o", "jsonpath={.status.operationState.phase}")
		if err != nil {
			return err
		}
		phase = strings.TrimSpace(string(out))
	}
	if phase == "Running" {
		return nil // auto-sync already started a new operation
	}
	if _, err := w.kubectl(ctx, "-n", "argocd", "patch", "applications.argoproj.io", name, "--type", "merge",
		"-p", string(patch)); err != nil {
		return fmt.Errorf("starting a new sync: %w", err)
	}
	w.log.Infof("%s: new sync started.", name)
	return nil
}
