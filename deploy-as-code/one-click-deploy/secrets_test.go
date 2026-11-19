package main

import (
	"errors"
	"os"
	"slices"
	"strings"
	"testing"
)

func TestSopsMethods(t *testing.T) {
	tests := map[string]struct {
		doc  string
		want []string
	}{
		"age":   {"a: ENC[x]\nsops:\n  age:\n    - recipient: age1abc\n  version: 3.10.2\n", []string{"age"}},
		"kms":   {"sops:\n  kms:\n    - arn: arn:aws:kms:x\n  age: []\n", []string{"kms"}},
		"azure": {"sops:\n  azure_kv:\n    - vault_url: https://v\n  kms: null\n", []string{"azure_kv"}},
		"both":  {"sops:\n  age: [ {recipient: a} ]\n  kms: [ {arn: b} ]\n", []string{"age", "kms"}},
	}
	for name, tt := range tests {
		t.Run(name, func(t *testing.T) {
			got, err := sopsMethods([]byte(tt.doc))
			if err != nil || !slices.Equal(got, tt.want) {
				t.Fatalf("got %v, %v; want %v", got, err, tt.want)
			}
		})
	}
	for _, bad := range []string{"plain: yaml\n", "sops:\n  age: []\n  kms: []\n"} {
		if _, err := sopsMethods([]byte(bad)); err == nil {
			t.Errorf("%q: expected an error", bad)
		}
	}
}

func TestCheckDeclaredMethod(t *testing.T) {
	if err := checkDeclaredMethod(sopsAge, []string{"age"}); err != nil {
		t.Error(err)
	}
	if err := checkDeclaredMethod(sopsKMS, []string{"age", "kms"}); err != nil {
		t.Error(err)
	}
	err := checkDeclaredMethod(sopsAzureKV, []string{"age"})
	if err == nil || !strings.Contains(err.Error(), "secrets.method is azure_kv, but the file is encrypted with age") {
		t.Errorf("err = %v", err)
	}
}

func TestRewriteK3sServer(t *testing.T) {
	raw := "apiVersion: v1\nclusters:\n- cluster:\n    certificate-authority-data: abc\n    server: https://127.0.0.1:6443\n  name: default\n"
	got, err := rewriteK3sServer([]byte(raw), "https://20.235.123.15:6443")
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(got), "    server: https://20.235.123.15:6443\n") || strings.Contains(string(got), "127.0.0.1") {
		t.Errorf("rewritten:\n%s", got)
	}
	if _, err := rewriteK3sServer([]byte("clusters: []\n"), "https://x"); err == nil {
		t.Error("expected an error when there is no server line")
	}
}

func TestDNSAdvice(t *testing.T) {
	a := ingressTarget{addr: "20.235.123.15", note: "the VM"}
	if ok, msg := dnsAdvice("d.org", a, []string{"20.235.123.15"}, []string{"20.235.123.15"}, nil); !ok {
		t.Errorf("matching A record: %s", msg)
	}
	if ok, msg := dnsAdvice("d.org", a, nil, []string{"20.235.123.15"}, errors.New("NXDOMAIN")); ok || !strings.Contains(msg, "an A record d.org -> 20.235.123.15") {
		t.Errorf("missing record: %s", msg)
	}
	if ok, msg := dnsAdvice("d.org", a, []string{"1.2.3.4"}, []string{"20.235.123.15"}, nil); ok || !strings.Contains(msg, "change it") {
		t.Errorf("wrong record: %s", msg)
	}
	lb := ingressTarget{addr: "abc.elb.amazonaws.com", hostname: true, note: "the LB"}
	if ok, msg := dnsAdvice("d.org", lb, []string{"5.6.7.8"}, []string{"5.6.7.8", "9.9.9.9"}, nil); !ok {
		t.Errorf("CNAME via shared IPs: %s", msg)
	}
	if _, msg := dnsAdvice("d.org", lb, nil, nil, errors.New("x")); !strings.Contains(msg, "a CNAME record d.org -> abc.elb.amazonaws.com") {
		t.Errorf("CNAME advice: %s", msg)
	}
}

func TestArgoCDDecryptionProblem(t *testing.T) {
	ageOverlay := []byte("volumes:\n  - name: sops-age\n    secret: { secretName: sops-age }\n")
	azureOverlay := []byte("serviceAccount:\n  annotations:\n    azure.workload.identity/client-id: abc\n")
	awsBase := []byte("env:\n  - name: AWS_ROLE_ARN\n    value: arn:aws:iam::1:role/x\n")
	tests := []struct {
		name            string
		method          string
		overlay, base   []byte
		wantProblemPart string
	}{
		{"age ok", sopsAge, ageOverlay, awsBase, ""},
		{"age without overlay", sopsAge, nil, awsBase, "does not mount the sops-age Secret"},
		{"kms ok", sopsKMS, nil, awsBase, ""},
		{"kms with age overlay", sopsKMS, ageOverlay, awsBase, "expect an age key"},
		{"kms without role", sopsKMS, nil, nil, "set no AWS role"},
		{"azure ok", sopsAzureKV, azureOverlay, awsBase, ""},
		{"azure without identity", sopsAzureKV, nil, awsBase, "no Workload Identity"},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			problem, hint := argoCDDecryptionProblem(tt.method, []string{tt.method}, readArgoCDWiring(tt.overlay, tt.base))
			if tt.wantProblemPart == "" && problem != "" {
				t.Errorf("unexpected problem: %s", problem)
			}
			if tt.wantProblemPart != "" && (!strings.Contains(problem, tt.wantProblemPart) || hint == "") {
				t.Errorf("problem = %q, hint = %q", problem, hint)
			}
		})
	}
}

// The branch's own files must pass for age (k3s-deployment).
func TestArgoCDWiringOnThisBranch(t *testing.T) {
	dir := "../helm/charts/backbone-services/argo-cd/"
	overlay, err := os.ReadFile(dir + "argo-cd-values.yaml")
	if err != nil {
		t.Skip("not on an age branch")
	}
	base, _ := os.ReadFile(dir + "values.yaml")
	if problem, _ := argoCDDecryptionProblem(sopsAge, []string{sopsAge}, readArgoCDWiring(overlay, base)); problem != "" {
		t.Error(problem)
	}
	azure, _ := os.ReadFile(dir + "values-azure-keyvault-sops.yaml")
	if problem, _ := argoCDDecryptionProblem(sopsAzureKV, []string{sopsAzureKV}, readArgoCDWiring(azure, base)); problem != "" {
		t.Errorf("values-azure-keyvault-sops.yaml used as argo-cd-values.yaml: %s", problem)
	}
}
