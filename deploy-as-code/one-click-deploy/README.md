# One-click deploy on k3s (single VM, from a Mac)

Sets up a full DIGIT environment on k3s on one VM with one command. The tool
installs Argo CD; Argo CD deploys everything else from the `k3s-deployment`
branch.

Tested: Azure VM (Ubuntu 22.04), run from macOS.

| Who | Does |
|---|---|
| Server owner | VM, k3s, ports, SSH access ([Step 1](#step-1-prepare-the-vm)) |
| Secrets owner | Age key ([Step 4](#step-4-get-the-age-key)) |
| DNS admin | A record → VM IP ([Step 8](#step-8-open-the-environment)) |
| You | Everything else |

---

## Step 1: Prepare the VM

**VM:** Ubuntu 22.04, 8 vCPU, 32 GB RAM, 128 GB disk (do not go smaller).

**Ports:**

| Port | Open to |
|---|---|
| 22, 6443 | Your IP |
| 80, 443 | Everyone |

**On the VM:**

```bash
# 1. New VM only: needed by Elasticsearch (kept across reboots and k3s reinstalls)
echo 'vm.max_map_count=262144' | sudo tee /etc/sysctl.d/99-digit-k3s.conf
sudo sysctl --system

# 2. Install k3s
curl -sfL https://get.k3s.io | sudo \
  INSTALL_K3S_VERSION=v1.35.9+k3s1 \
  INSTALL_K3S_EXEC="server --disable traefik --write-kubeconfig-mode 644 --tls-san <VM IP>" \
  sh -

# 3. Check
sudo k3s kubectl get node                     # Ready, v1.35.9+k3s1
sudo systemctl cat k3s | grep -A8 ExecStart    # shows --tls-san <VM IP>
```

> The settings must come **after** `sudo`. Placed before it, sudo drops them
> and k3s installs with defaults (wrong version, no `--tls-san`, then an
> `x509` error from your Mac).

Optional, for `kubectl` on the VM itself:

```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config && chmod 600 ~/.kube/config
```

---

## Step 2: Install the tools (Mac)

```bash
brew install git go kubectl helm sops
```

---

## Step 3: Get the repo and check SSH

```bash
git clone https://github.com/egovernments/DIGIT-DevOps.git ~/DIGIT-DevOps
cd ~/DIGIT-DevOps && git checkout k3s-deployment && git pull

chmod 600 ~/.ssh/k3s-sandbox-key
ssh -i ~/.ssh/k3s-sandbox-key <ssh user>@<VM IP> 'echo ok'      # prints ok
```

`git status` must show no changes: the tool refuses to run if your checkout
differs from GitHub.

---

## Step 4: Get the age key

Get the age private key file from the secrets owner (sent securely, never by
email, chat or git) and check it:

```bash
chmod 600 ~/k3s-deployment.agekey
cd ~/DIGIT-DevOps/deploy-as-code/helm
SOPS_AGE_KEY_FILE=~/k3s-deployment.agekey \
  sops -d environments/k3s-deployment-secrets.yaml > /dev/null && echo "decrypts OK"
```

To edit a secret later: `SOPS_AGE_KEY_FILE=~/k3s-deployment.agekey sops environments/k3s-deployment-secrets.yaml`,
check `git diff` shows only `ENC[...]`, then commit and push.

---

## Step 5: Write the config file

```bash
cd ~/DIGIT-DevOps/deploy-as-code/one-click-deploy
cp clusters/example-k3s.yaml clusters/<name>.yaml        # git ignores it
```

Fill in every `<placeholder>`:

| Field | Example |
|---|---|
| `name` | `k3s-sandbox` |
| `env`, `branch` | `k3s-deployment` |
| `domain` | `k3s-deployment.digit.org` |
| `cluster.k3s.host` | VM IP |
| `cluster.k3s.sshUser` | `azureuser` |
| `cluster.k3s.sshKeyFile` | `~/.ssh/k3s-sandbox-key` |
| `secrets.ageKeyFile` | `~/k3s-deployment.agekey` |

For a one-click run set `options.assumeYes: true`: only *"Is the right
cluster?"* is asked. Keep `skipGitCheck: false`.

---

## Step 6: Check the cluster (read-only)

```bash
go run . status -f clusters/<name>.yaml
```

Shows the node, apps, DNS and Kong. On a new VM "Argo CD not installed" is
expected.

---

## Step 7: Run the setup

```bash
go run . all -f clusters/<name>.yaml
```

About 15–25 minutes:

1. Confirms the cluster (always asked)
2. Checks tools, cluster-admin, git and the age key (nothing changes before this passes)
3. Installs Argo CD and cluster configs, then the bootstrap; Argo CD deploys the rest from GitHub
4. Waits until the platform apps are healthy (up to 20 min)
5. Checks DNS (warning only), then configures Kong

Ends with the Kong summary. Safe to rerun; it never deletes anything. If
Argo CD gets stuck *waiting for completion of hook* on a first install, the
tool restarts that app's sync by itself.

---

## Step 8: Open the environment

If Step 7 warned about DNS, ask for an **A record** `<domain>` → `<VM IP>`.
HTTPS is issued automatically after that.

| What | URL | Login |
|---|---|---|
| DIGIT | `https://<domain>` | |
| Argo CD | `https://<domain>/argocd` | `admin` (change the password after first login) |
| Grafana | `https://<domain>/monitoring` | see below |
| Jaeger | `https://<domain>/jaeger` | |

Passwords (need [kubectl from your Mac](#kubectl-from-your-mac)):

```bash
kubectl --context <name> -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl --context <name> -n monitoring get secret grafana-oauth -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl --context <name> -n monitoring get secret grafana-oauth -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

From now on, change things in git (push to `k3s-deployment`); Argo CD applies
them.

---

## kubectl from your Mac

```bash
kubectl config delete-context <name>; kubectl config delete-cluster <name>; kubectl config delete-user <name>   # after a reinstall

ssh -i ~/.ssh/k3s-sandbox-key <ssh user>@<VM IP> 'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed -e 's/127.0.0.1/<VM IP>/' -e 's/: default$/: <name>/' > ~/.kube/<name>.yaml
KUBECONFIG=~/.kube/config:~/.kube/<name>.yaml kubectl config view --flatten > ~/.kube/merged \
  && mv ~/.kube/merged ~/.kube/config

kubectl --context <name> get nodes
```

---

## If something fails

The error says what to do next (`Next:`). Fix it and rerun the same command.

| Error | Fix |
|---|---|
| `config file ... is not complete` | Fill in the listed fields |
| `reading k3s.yaml over SSH` | SSH check in Step 3; port 22 open to you |
| `cannot reach the API server` / `x509` | Port 6443 open to you; k3s installed with `--tls-san` (Step 1) |
| `differs from origin` / `uncommitted changes` | `git pull`; commit or discard local changes |
| `cannot decrypt ... with age` | Wrong age key (Step 4) |
| Platform apps timed out | `status` shows which app; fix in git, push, then `go run . backbone -f clusters/<name>.yaml` |
| Elasticsearch keeps restarting | `vm.max_map_count` missing (Step 1) |
| No HTTPS certificate | DNS record, and ports 80/443 open to everyone |
| Kong failed | `go run . kong -f clusters/<name>.yaml` |

Don't run two at once, and don't fix things by hand in the cluster (Argo CD
puts back what is in git).

---

## Start over

```bash
ssh -i ~/.ssh/k3s-sandbox-key <ssh user>@<VM IP>
sudo /usr/local/bin/k3s-uninstall.sh          # deletes the cluster and all data
```

Then Step 1 (install and check), [kubectl from your Mac](#kubectl-from-your-mac), and Step 7.
