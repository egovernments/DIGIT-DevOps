package main

import (
	"encoding/json"
	"testing"
)

// Shape of the keycloak Application while stuck on a vanished hook Job.
const stuckKeycloak = `{
  "spec": {
    "source": {"targetRevision": "k3s-deployment"},
    "syncPolicy": {"syncOptions": ["ApplyOutOfSyncOnly=true", "ServerSideApply=true", "CreateNamespace=true"]}
  },
  "status": {"operationState": {
    "phase": "Running",
    "message": "waiting for completion of hook batch/Job/keycloak-db-create",
    "syncResult": {"resources": [
      {"group": "batch", "kind": "Job", "namespace": "keycloak", "name": "keycloak-db-create", "hookType": "PreSync", "hookPhase": "Running"},
      {"group": "apps", "kind": "Deployment", "namespace": "keycloak", "name": "keycloak"}
    ]}
  }}
}`

func decodeHookApp(t *testing.T, s string) hookApp {
	t.Helper()
	var a hookApp
	if err := json.Unmarshal([]byte(s), &a); err != nil {
		t.Fatal(err)
	}
	return a
}

func TestRunningHooks(t *testing.T) {
	hooks := runningHooks(decodeHookApp(t, stuckKeycloak))
	if len(hooks) != 1 {
		t.Fatalf("got %d hooks, want 1: %+v", len(hooks), hooks)
	}
	h := hooks[0]
	if h.kubectlRef() != "job.batch" || h.Namespace != "keycloak" || h.Name != "keycloak-db-create" {
		t.Errorf("unexpected hook %+v (ref %q)", h, h.kubectlRef())
	}
	if h.String() != "batch/Job/keycloak-db-create" {
		t.Errorf("String() = %q", h.String())
	}
}

func TestRunningHooksIgnoresOtherStates(t *testing.T) {
	for name, s := range map[string]string{
		"succeeded":    `{"status":{"operationState":{"phase":"Succeeded","message":"successfully synced"}}}`,
		"no operation": `{"status":{}}`,
		"other wait": `{"status":{"operationState":{"phase":"Running","message":"waiting for healthy state of /Service/x",
			"syncResult":{"resources":[{"kind":"Job","name":"j","hookType":"PreSync","hookPhase":"Running"}]}}}}`,
		"hook done": `{"status":{"operationState":{"phase":"Running","message":"waiting for completion of hook batch/Job/j",
			"syncResult":{"resources":[{"kind":"Job","name":"j","hookType":"PreSync","hookPhase":"Succeeded"}]}}}}`,
	} {
		if hooks := runningHooks(decodeHookApp(t, s)); len(hooks) != 0 {
			t.Errorf("%s: got %+v, want none", name, hooks)
		}
	}
}

func TestCoreGroupRef(t *testing.T) {
	h := hookResource{Kind: "ServiceAccount", Name: "ingress-nginx-admission"}
	if h.kubectlRef() != "serviceaccount" || h.String() != "ServiceAccount/ingress-nginx-admission" {
		t.Errorf("ref %q, string %q", h.kubectlRef(), h.String())
	}
}

func TestSyncRestartPatch(t *testing.T) {
	p, err := syncRestartPatch(decodeHookApp(t, stuckKeycloak))
	if err != nil {
		t.Fatal(err)
	}
	var got struct {
		Operation struct {
			InitiatedBy struct{ Username string } `json:"initiatedBy"`
			Sync        struct {
				Revision    string   `json:"revision"`
				SyncOptions []string `json:"syncOptions"`
			} `json:"sync"`
		} `json:"operation"`
	}
	if err := json.Unmarshal(p, &got); err != nil {
		t.Fatal(err)
	}
	if got.Operation.Sync.Revision != "k3s-deployment" || len(got.Operation.Sync.SyncOptions) != 3 ||
		got.Operation.InitiatedBy.Username != "one-click-deploy" {
		t.Errorf("unexpected patch %s", p)
	}
	if _, err := syncRestartPatch(hookApp{}); err == nil {
		t.Error("want an error without a target revision")
	}
}
