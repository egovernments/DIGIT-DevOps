package main

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"sort"
	"strings"
	"text/tabwriter"
	"time"
)

const backbonePollInterval = 10 * time.Second

// While nothing changes, a "still waiting" line is printed this often, so a
// long Elasticsearch or Kafka start does not look like a hang.
const heartbeatInterval = time.Minute

// A run tolerates this many consecutive kubectl failures while polling (API
// server restarts, network blips) before giving up.
const maxPollFailures = 3

type applicationSet struct {
	Spec struct {
		Generators []struct {
			List *struct {
				Elements []map[string]any `json:"elements"`
			} `json:"list"`
		} `json:"generators"`
		Template struct {
			Metadata struct {
				Name string `json:"name"`
			} `json:"metadata"`
		} `json:"template"`
	} `json:"spec"`
}

type application struct {
	Metadata struct {
		Name string `json:"name"`
	} `json:"metadata"`
	Status struct {
		Sync struct {
			Status string `json:"status"`
		} `json:"sync"`
		Health struct {
			Status  string `json:"status"`
			Message string `json:"message"`
		} `json:"health"`
		Conditions []struct {
			Type    string `json:"type"`
			Message string `json:"message"`
		} `json:"conditions"`
		OperationState *struct {
			Phase   string `json:"phase"`
			Message string `json:"message"`
		} `json:"operationState"`
	} `json:"status"`
}

type applicationList struct {
	Items []application `json:"items"`
}

type appState struct {
	Name, Sync, Health, Detail string
}

func (s appState) ready() bool { return s.Sync == "Synced" && s.Health == "Healthy" }

// expectedApps returns the Application names the appset's list generators
// produce. Reading them from the cluster keeps this in step with the YAML
// without a second hard-coded list.
func expectedApps(set applicationSet) ([]string, error) {
	tmpl := set.Spec.Template.Metadata.Name
	if tmpl == "" {
		return nil, errors.New("ApplicationSet has no spec.template.metadata.name")
	}
	var names []string
	for _, g := range set.Spec.Generators {
		if g.List == nil {
			continue
		}
		for i, el := range g.List.Elements {
			name, ok := el["name"].(string)
			if !ok || name == "" {
				return nil, fmt.Errorf("list element %d has no string `name`", i)
			}
			app := strings.ReplaceAll(tmpl, "{{name}}", name)
			if strings.Contains(app, "{{") {
				return nil, fmt.Errorf("template name %q uses parameters other than {{name}}", tmpl)
			}
			names = append(names, app)
		}
	}
	if len(names) == 0 {
		return nil, errors.New("ApplicationSet has no list generator elements")
	}
	return names, nil
}

// backboneStates reports one row per expected Application, including the ones
// the ApplicationSet controller has not generated yet.
func backboneStates(expected []string, apps applicationList) []appState {
	byName := make(map[string]application, len(apps.Items))
	for _, a := range apps.Items {
		byName[a.Metadata.Name] = a
	}
	states := make([]appState, 0, len(expected))
	for _, name := range expected {
		a, ok := byName[name]
		if !ok {
			states = append(states, appState{Name: name, Sync: "-", Health: "-", Detail: "not generated yet"})
			continue
		}
		s := appState{Name: name, Sync: orDash(a.Status.Sync.Status), Health: orDash(a.Status.Health.Status)}
		switch {
		case len(a.Status.Conditions) > 0:
			s.Detail = a.Status.Conditions[0].Type + ": " + a.Status.Conditions[0].Message
		case a.Status.OperationState != nil && a.Status.OperationState.Phase != "Succeeded" && a.Status.OperationState.Message != "":
			s.Detail = a.Status.OperationState.Phase + ": " + a.Status.OperationState.Message
		default:
			s.Detail = a.Status.Health.Message
		}
		states = append(states, s)
	}
	sort.Slice(states, func(i, j int) bool { return states[i].Name < states[j].Name })
	return states
}

// backboneAppSets are the ApplicationSets whose Applications must be healthy
// before application services can start. By default: ingress, cert-manager,
// Elasticsearch and Kafka from the backbone appset, and Postgres, Keycloak and
// Kong from the platform appset. The config file's waitFor.appSets changes the
// list; "{env}" in a name is replaced by the environment.
func (w *Workflow) backboneAppSets() []string {
	sets := make([]string, len(w.cfg.AppSets))
	for i, s := range w.cfg.AppSets {
		sets[i] = strings.ReplaceAll(s, "{env}", w.cfg.Env)
	}
	return sets
}

// backboneSnapshot reads the appsets and Applications once. It wraps errNotYet
// while the bootstrap has not created an appset.
func (w *Workflow) backboneSnapshot(ctx context.Context) ([]appState, error) {
	var expected []string
	for _, name := range w.backboneAppSets() {
		out, err := w.kubectl(ctx, "-n", "argocd", "get", "applicationsets.argoproj.io", name, "-o", "json")
		if isNotFound(err) {
			return nil, fmt.Errorf("%w: ApplicationSet argocd/%s does not exist (the bootstrap app creates it once the appset is on origin/%s)",
				errNotYet, name, w.cfg.Branch)
		}
		if err != nil {
			return nil, err
		}
		var set applicationSet
		if err := json.Unmarshal(out, &set); err != nil {
			return nil, fmt.Errorf("decoding ApplicationSet %s: %w", name, err)
		}
		names, err := expectedApps(set)
		if err != nil {
			return nil, fmt.Errorf("ApplicationSet %s: %w", name, err)
		}
		expected = append(expected, names...)
	}

	out, err := w.kubectl(ctx, "-n", "argocd", "get", "applications.argoproj.io", "-o", "json")
	if err != nil {
		return nil, err
	}
	var apps applicationList
	if err := json.Unmarshal(out, &apps); err != nil {
		return nil, fmt.Errorf("decoding Applications: %w", err)
	}
	return backboneStates(expected, apps), nil
}

// waitBackbone polls until every backbone and platform Application is Synced
// and Healthy.
// Degraded is not treated as final -- Argo CD keeps retrying and a pod may
// still recover -- so only the timeout ends the wait with an error.
func (w *Workflow) waitBackbone(ctx context.Context) error {
	w.log.Banner("BACKBONE SERVICES -> " + strings.Join(w.backboneAppSets(), ", "))
	timeout := w.cfg.BackboneTimeout
	w.log.Infof("Waiting up to %s for the backbone Applications to be Synced and Healthy.", timeout)

	start := time.Now()
	deadline := start.Add(timeout)
	lastPrint := start
	ticker := time.NewTicker(backbonePollInterval)
	defer ticker.Stop()

	var (
		last     string
		states   []appState
		failures int
		lastErr  error
	)
	for {
		snap, err := w.backboneSnapshot(ctx)
		switch {
		case err == nil:
			failures, lastErr, states = 0, nil, snap
			if table := formatStates(states); table != last {
				w.log.Block(table)
				fmt.Fprintln(w.log.out)
				last, lastPrint = table, time.Now()
			} else if !allReady(states) && time.Since(lastPrint) >= heartbeatInterval {
				w.log.Infof("Still waiting (%s of %s): %s", time.Since(start).Round(time.Second), timeout, notReadySummary(states, nil))
				lastPrint = time.Now()
			}
			if allReady(states) {
				w.log.Successf("All %d backbone Applications are Synced and Healthy.", len(states))
				return nil
			}
		case errors.Is(err, errNotYet):
			if lastErr == nil || lastErr.Error() != err.Error() {
				w.log.Infof("%v", err)
			}
			lastErr = err
		case ctx.Err() != nil:
			return ctx.Err()
		default:
			failures++
			lastErr = err
			if failures >= maxPollFailures {
				return stepErr("backbone", "kubectl -n argocd get applications", err)
			}
			w.log.Warnf("Polling failed (%d/%d), retrying: %v", failures, maxPollFailures, err)
		}

		if time.Now().After(deadline) {
			return stepErr("backbone", "kubectl -n argocd describe application <name>, then check that app's pods",
				fmt.Errorf("not ready after %s: %s", timeout, notReadySummary(states, lastErr)))
		}
		select {
		case <-ctx.Done():
			return ctx.Err()
		case <-ticker.C:
		}
	}
}

func allReady(states []appState) bool {
	for _, s := range states {
		if !s.ready() {
			return false
		}
	}
	return len(states) > 0
}

func notReadySummary(states []appState, lastErr error) string {
	var parts []string
	for _, s := range states {
		if !s.ready() {
			parts = append(parts, fmt.Sprintf("%s (%s/%s)", s.Name, s.Sync, s.Health))
		}
	}
	if len(parts) == 0 && lastErr != nil {
		return lastErr.Error()
	}
	return strings.Join(parts, ", ")
}

func formatStates(states []appState) string {
	var buf bytes.Buffer
	tw := tabwriter.NewWriter(&buf, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "APPLICATION\tSYNC\tHEALTH\tDETAIL")
	for _, s := range states {
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\n", s.Name, s.Sync, s.Health, truncate(s.Detail, 90))
	}
	tw.Flush()
	return buf.String()
}

func orDash(s string) string {
	if s == "" {
		return "-"
	}
	return s
}

func truncate(s string, n int) string {
	s = strings.Join(strings.Fields(s), " ")
	if len(s) <= n {
		return s
	}
	return s[:n-3] + "..."
}
