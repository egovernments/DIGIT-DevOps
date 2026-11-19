package main

import (
	"encoding/json"
	"strings"
	"testing"
)

const appSetJSON = `{
  "spec": {
    "generators": [{"list": {"elements": [
      {"name": "ingress-nginx", "namespace": "egov"},
      {"name": "kafka-kraft", "namespace": "backbone"}
    ]}}],
    "template": {"metadata": {"name": "backbone-{{name}}"}}
  }
}`

func mustAppSet(t *testing.T, s string) applicationSet {
	t.Helper()
	var set applicationSet
	if err := json.Unmarshal([]byte(s), &set); err != nil {
		t.Fatal(err)
	}
	return set
}

func TestExpectedApps(t *testing.T) {
	got, err := expectedApps(mustAppSet(t, appSetJSON))
	if err != nil {
		t.Fatal(err)
	}
	if strings.Join(got, ",") != "backbone-ingress-nginx,backbone-kafka-kraft" {
		t.Errorf("got %v", got)
	}
}

func TestExpectedAppsErrors(t *testing.T) {
	tests := map[string]string{
		"no template name":   `{"spec":{"generators":[{"list":{"elements":[{"name":"a"}]}}]}}`,
		"element no name":    `{"spec":{"generators":[{"list":{"elements":[{"path":"a"}]}}],"template":{"metadata":{"name":"x-{{name}}"}}}}`,
		"other template var": `{"spec":{"generators":[{"list":{"elements":[{"name":"a"}]}}],"template":{"metadata":{"name":"{{path}}"}}}}`,
		"no elements":        `{"spec":{"generators":[{"git":{}}],"template":{"metadata":{"name":"x-{{name}}"}}}}`,
	}
	for name, js := range tests {
		t.Run(name, func(t *testing.T) {
			if _, err := expectedApps(mustAppSet(t, js)); err == nil {
				t.Fatal("expected an error")
			}
		})
	}
}

func TestBackboneStates(t *testing.T) {
	var apps applicationList
	err := json.Unmarshal([]byte(`{"items":[
	  {"metadata":{"name":"backbone-ingress-nginx"},"status":{"sync":{"status":"Synced"},"health":{"status":"Healthy"}}},
	  {"metadata":{"name":"backbone-kafka-kraft"},"status":{"sync":{"status":"OutOfSync"},"health":{"status":"Degraded"},
	    "conditions":[{"type":"SyncError","message":"pvc pending"}]}},
	  {"metadata":{"name":"account"},"status":{"sync":{"status":"Synced"},"health":{"status":"Healthy"}}}
	]}`), &apps)
	if err != nil {
		t.Fatal(err)
	}

	states := backboneStates([]string{"backbone-kafka-kraft", "backbone-ingress-nginx", "backbone-cert-manager"}, apps)
	if len(states) != 3 {
		t.Fatalf("got %d states, want 3 (unrelated apps excluded, missing ones included)", len(states))
	}
	byName := map[string]appState{}
	for _, s := range states {
		byName[s.Name] = s
	}
	if !byName["backbone-ingress-nginx"].ready() {
		t.Error("ingress-nginx should be ready")
	}
	if s := byName["backbone-kafka-kraft"]; s.ready() || s.Detail != "SyncError: pvc pending" {
		t.Errorf("kafka-kraft = %+v", s)
	}
	if s := byName["backbone-cert-manager"]; s.ready() || s.Detail != "not generated yet" {
		t.Errorf("cert-manager = %+v", s)
	}
	if allReady(states) {
		t.Error("allReady should be false")
	}
	if allReady(nil) {
		t.Error("allReady(nil) should be false")
	}
	if !strings.Contains(notReadySummary(states, nil), "backbone-kafka-kraft (OutOfSync/Degraded)") {
		t.Errorf("summary = %q", notReadySummary(states, nil))
	}
}
