package main

import (
	"context"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
)

// fakeCLIs puts stand-ins for ssh, aws, az and kubelogin first on PATH. Each
// appends its argv to a log; aws and az write a kubeconfig where the real
// ones would, so the fetch functions run end to end without a cloud.
func fakeCLIs(t *testing.T, aad bool) (logFile string) {
	t.Helper()
	dir := t.TempDir()
	logFile = filepath.Join(dir, "calls.log")
	kubeconfig := `apiVersion: v1
kind: Config
clusters:
- cluster: { server: https://example:443 }
  name: c
contexts:
- context: { cluster: c, user: u }
  name: NAME
current-context: NAME
users:
- name: u
  user: { token: t }
`
	if aad {
		kubeconfig = strings.Replace(kubeconfig, "user: { token: t }", "user: { exec: { apiVersion: client.authentication.k8s.io/v1beta1, command: kubelogin } }", 1)
	}
	scripts := map[string]string{
		"ssh": `printf 'apiVersion: v1\nclusters:\n- cluster:\n    server: https://127.0.0.1:6443\n  name: default\ncontexts:\n- context:\n    cluster: default\n    user: default\n  name: default\ncurrent-context: default\nkind: Config\nusers:\n- name: default\n  user:\n    token: t\n'`,
		"aws": `case "$1" in
  sts) echo arn:aws:iam::123:user/op ;;
  eks) while [ $# -gt 0 ]; do [ "$1" = --kubeconfig ] && out=$2; [ "$1" = --alias ] && name=$2; shift; done
       cat > "$out" <<'EOF'
` + kubeconfig + `EOF
       sed -i.bak "s/NAME/$name/" "$out" ;;
esac`,
		"az": `case "$1" in
  account) echo op@example.org ;;
  aks) while [ $# -gt 0 ]; do [ "$1" = --file ] && out=$2; [ "$1" = --context ] && name=$2; shift; done
       cat > "$out" <<'EOF'
` + kubeconfig + `EOF
       sed -i.bak "s/NAME/$name/" "$out" ;;
esac`,
		"kubelogin": `:`,
	}
	for name, body := range scripts {
		script := "#!/bin/sh\necho \"" + name + " $*\" >> " + logFile + "\n" + body + "\n"
		if err := os.WriteFile(filepath.Join(dir, name), []byte(script), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	t.Setenv("PATH", dir+string(os.PathListSeparator)+os.Getenv("PATH"))
	return logFile
}

func fetchWorkflow(t *testing.T, cfg *Config) *Workflow {
	t.Helper()
	cfg.Name = "target"
	w := &Workflow{cfg: cfg, log: &Logger{out: io.Discard, errOut: io.Discard}, run: newRunner()}
	t.Cleanup(w.Close)
	return w
}

func readCalls(t *testing.T, logFile string) string {
	t.Helper()
	b, err := os.ReadFile(logFile)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func currentContext(t *testing.T, kubeconfig string) string {
	t.Helper()
	out, err := exec.Command("kubectl", "--kubeconfig", kubeconfig, "config", "current-context").Output()
	if err != nil {
		t.Fatal(err)
	}
	return strings.TrimSpace(string(out))
}

func requireKubectl(t *testing.T) {
	if _, err := exec.LookPath("kubectl"); err != nil {
		t.Skip("kubectl not installed")
	}
}

func TestFetchK3s(t *testing.T) {
	requireKubectl(t)
	logFile := fakeCLIs(t, false)
	key := filepath.Join(t.TempDir(), "id")
	os.WriteFile(key, []byte("k"), 0o600)
	w := fetchWorkflow(t, &Config{Provider: "k3s", K3s: K3sCluster{Host: "20.1.2.3", SSHUser: "azureuser", SSHKeyFile: key, SSHPort: 22, APIPort: 6443}})

	if err := w.fetchKubeconfig(context.Background()); err != nil {
		t.Fatal(err)
	}
	calls := readCalls(t, logFile)
	if !strings.Contains(calls, "ssh -i "+key+" -p 22 -o BatchMode=yes") || !strings.Contains(calls, "azureuser@20.1.2.3 sudo -n cat /etc/rancher/k3s/k3s.yaml") {
		t.Errorf("ssh call:\n%s", calls)
	}
	kc, _ := os.ReadFile(w.kubeconfig)
	if !strings.Contains(string(kc), "server: https://20.1.2.3:6443") {
		t.Errorf("server not rewritten:\n%s", kc)
	}
	if got := currentContext(t, w.kubeconfig); got != "target" {
		t.Errorf("current-context = %q, want the config name", got)
	}
}

func TestFetchEKS(t *testing.T) {
	requireKubectl(t)
	logFile := fakeCLIs(t, false)
	w := fetchWorkflow(t, &Config{Provider: "eks", EKS: EKSCluster{Name: "digit", Region: "ap-south-1", Profile: "egov", RoleARN: "arn:aws:iam::1:role/admin"}})

	if err := w.fetchKubeconfig(context.Background()); err != nil {
		t.Fatal(err)
	}
	calls := readCalls(t, logFile)
	for _, want := range []string{
		"aws sts get-caller-identity --query Arn --output text --profile egov",
		"aws eks update-kubeconfig --name digit --region ap-south-1 --kubeconfig " + w.kubeconfig + " --alias target --role-arn arn:aws:iam::1:role/admin --profile egov",
	} {
		if !strings.Contains(calls, want) {
			t.Errorf("missing call %q in:\n%s", want, calls)
		}
	}
	if got := currentContext(t, w.kubeconfig); got != "target" {
		t.Errorf("current-context = %q", got)
	}
}

func TestFetchAKS(t *testing.T) {
	requireKubectl(t)
	for _, aad := range []bool{false, true} {
		logFile := fakeCLIs(t, aad)
		w := fetchWorkflow(t, &Config{Provider: "aks", AKS: AKSCluster{Name: "uat", ResourceGroup: "rg", Subscription: "sub"}})

		if err := w.fetchKubeconfig(context.Background()); err != nil {
			t.Fatalf("aad=%v: %v", aad, err)
		}
		calls := readCalls(t, logFile)
		if !strings.Contains(calls, "az account show") ||
			!strings.Contains(calls, "az aks get-credentials --name uat --resource-group rg --file "+w.kubeconfig+" --context target --overwrite-existing --subscription sub") {
			t.Errorf("aad=%v az calls:\n%s", aad, calls)
		}
		converted := strings.Contains(calls, "kubelogin convert-kubeconfig -l azurecli --kubeconfig "+w.kubeconfig)
		if converted != aad {
			t.Errorf("aad=%v: kubelogin convert called = %v\n%s", aad, converted, calls)
		}
		if got := currentContext(t, w.kubeconfig); got != "target" {
			t.Errorf("aad=%v: current-context = %q", aad, got)
		}
		w.Close()
	}
}
