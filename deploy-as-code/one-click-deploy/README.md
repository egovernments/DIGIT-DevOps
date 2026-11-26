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

- **[Part 1: Set up an environment](#part-1-set-up-an-environment):** deploy `k3s-deployment` (or any branch already set up) on a VM
- **[Part 2: Create a new k3s environment](#part-2-create-a-new-k3s-environment):** a new branch with its own name, domain and secrets; then do Part 1

---

# Part 1: Set up an environment

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

To edit a secret later (from `deploy-as-code/helm`, where `.sops.yaml` is): `SOPS_AGE_KEY_FILE=~/k3s-deployment.agekey sops environments/k3s-deployment-secrets.yaml`,
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

Passwords (need [kubectl from your Mac](#reference-kubectl-from-your-mac)):

```bash
kubectl --context <name> -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
kubectl --context <name> -n monitoring get secret grafana-oauth -o jsonpath='{.data.admin-user}' | base64 -d; echo
kubectl --context <name> -n monitoring get secret grafana-oauth -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

From now on, change things in git (push to `k3s-deployment`); Argo CD applies
them.

---

## Step 9: Set up license-certificate (after the first run)

### Master tenant

license-certificate needs the code of the master tenant (base tenant). It only
exists after you create it, so set it after the first run.

- Create the base tenant: `POST https://<domain>/accounts/v3/tenants`. Note
  its tenant code (e.g. `BASETENANT`).
- In `helm/environments/k3s-deployment.yaml`, under `license-certificate:`, set
  both to that code:

  ```yaml
  license-certificate:
    master-tenant-schema: "<tenant code>"              # MASTER_TENANT_SCHEMA
    certificate-master-tenant-schema: "<tenant code>"  # CERTIFICATE_MASTER_TENANT_SCHEMA
  ```

- Commit on a branch, PR to `k3s-deployment`, merge. Argo CD restarts
  license-certificate with the new value. Check:
  `kubectl --context <name> -n egov get deploy license-certificate -o yaml | grep -A1 MASTER_TENANT_SCHEMA`

### Metabase keys

Used by **license-certificate** only. They exist only after Metabase is set
up, so the values in sops are not valid on a new install.

| sops key (`environments/k3s-deployment-secrets.yaml`) | Kubernetes secret / key | Env var in license-certificate |
|---|---|---|
| `cluster-configs.secrets.egov-metabase.egov-metabase-api-key` | `egov/egov-metabase` / `egov-metabase-api-key` | `EGOV_METABASE_API_KEY` |
| `cluster-configs.secrets.egov-metabase.egov-metabase-secret-key` | `egov/egov-metabase` / `egov-metabase-secret-key` | `EGOV_METABASE_SECRET_KEY` |

Plus 2 IDs (not secrets) in `helm/charts/core-services/license-certificate/values.yaml`:
`EGOV_METABASE_DATABASE_ID` (`2`) and `EGOV_METABASE_COLLECTION_ID` (`5`).

**Get the values** (`https://<domain>/metabase`):

- Create the admin user.
- Add a database: PostgreSQL, host `postgres.egov`, port `5432`, database
  `postgres`, login from the `db` secret
  (`kubectl --context <name> -n egov get secret db -o jsonpath='{.data.username}' | base64 -d`, same for `.data.password`).
- Settings → Admin settings → **API keys** → Create API key (Admin group)
  → copy it → `egov-metabase-api-key`.
- Admin settings → **Embedding** → create the **embedding secret key** →
  copy it → `egov-metabase-secret-key`.
- Create a collection for the certificate dashboards.
- Check the IDs in the URLs (`/admin/databases/<id>`, `/collection/<id>-...`).
  If they are not `2` and `5`, change them in the values file above.

**Save and apply:**

```bash
cd ~/DIGIT-DevOps/deploy-as-code/helm
git checkout k3s-deployment && git pull && git checkout -b fix/metabase-keys
SOPS_AGE_KEY_FILE=~/k3s-deployment.agekey sops environments/k3s-deployment-secrets.yaml
#   under cluster-configs.secrets.egov-metabase: paste the 2 values, save
git diff                          # only ENC[...] lines changed
git commit -am "fix(k3s-deployment): Metabase keys for license-certificate"
git push -u origin fix/metabase-keys            # PR to k3s-deployment, merge
```

After the merge:

```bash
kubectl --context <name> -n argocd annotate application k3s-deployment-cluster-configs argocd.argoproj.io/refresh=hard --overwrite
kubectl --context <name> -n egov rollout restart deploy/license-certificate
kubectl --context <name> -n egov logs deploy/license-certificate | grep -i metabase | grep -iE "error|401|403"   # prints nothing
```

---

> **The setup is complete.** The sections below are reference: use them only
> when you need them (kubectl access, errors, reinstall).

## Reference: kubectl from your Mac

```bash
kubectl config delete-context <name>; kubectl config delete-cluster <name>; kubectl config delete-user <name>   # after a reinstall

ssh -i ~/.ssh/k3s-sandbox-key <ssh user>@<VM IP> 'sudo cat /etc/rancher/k3s/k3s.yaml' \
  | sed -e 's/127.0.0.1/<VM IP>/' -e 's/: default$/: <name>/' > ~/.kube/<name>.yaml
KUBECONFIG=~/.kube/config:~/.kube/<name>.yaml kubectl config view --flatten > ~/.kube/merged \
  && mv ~/.kube/merged ~/.kube/config

kubectl --context <name> get nodes
```

---

## Reference: If something fails

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

## Reference: Start over

```bash
ssh -i ~/.ssh/k3s-sandbox-key <ssh user>@<VM IP>
sudo /usr/local/bin/k3s-uninstall.sh          # deletes the cluster and all data
```

Then Step 1 (install and check), [kubectl from your Mac](#reference-kubectl-from-your-mac), and Step 7.

---

# Part 2: Create a new k3s environment

A new environment `<env>` with its own branch, domain and secrets, copied
from `k3s-deployment`. Here `<env>` is both the environment and the branch
name, `<domain>` its domain. Afterwards, run Part 1 with the new names.

## Step 1: Create the branch and rename the files

```bash
git checkout k3s-deployment && git pull
git checkout -b <env>
cd deploy-as-code/helm

# Rename the environment's files
git mv environments/k3s-deployment.yaml               environments/<env>.yaml
git mv environments/k3s-deployment-backbone           environments/<env>-backbone
git mv charts/monitoring/values/k3s-deployment        charts/monitoring/values/<env>
git mv charts/argo-cd/bootstrap/k3s-deployment-bootstrap.yaml       charts/argo-cd/bootstrap/<env>-bootstrap.yaml
git mv charts/argo-cd/backbone/k3s-deployment-backbone-appset.yaml  charts/argo-cd/backbone/<env>-backbone-appset.yaml
for f in charts/argo-cd/egov/k3s-deployment-egov-appset-*.yaml; do git mv "$f" "${f/k3s-deployment/<env>}"; done

# Replace the domain first, then the environment / branch name
grep -rl 'k3s-deployment\.digit\.org' charts environments | xargs sed -i '' 's/k3s-deployment\.digit\.org/<domain>/g'
grep -rl 'k3s-deployment' charts/argo-cd charts/monitoring/values/<env> environments/<env>.yaml environments/<env>-backbone \
  | xargs sed -i '' 's/k3s-deployment/<env>/g'

# Check: only comments may be left
grep -rn 'k3s-deployment' charts/argo-cd environments/<env>.yaml environments/<env>-backbone charts/monitoring/values/<env>
```

The domain is also hard-coded in 4 chart values files (account, employee,
keycloak, ui-access-control); the domain replacement covers them.

## Step 2: Create the secrets

**What:** `environments/<env>-secrets.yaml` holds the environment's passwords
and tokens (database, Keycloak, Kafka, Elasticsearch, ...). It is committed
**encrypted** with SOPS. Each environment has its **own age key**; whoever
has the key can read and edit the file, nobody else can.

**Who:** the secrets owner. Run from `deploy-as-code/helm`.

1. **Create the key**

   ```bash
   brew install age                    # once, for age-keygen
   age-keygen -o ~/<env>.agekey        # prints "Public key: age1..."
   chmod 600 ~/<env>.agekey
   ```

   The **public key** (`age1...`) goes in git. The **key file** never does:
   keep it safe and send it to the operator only through a password manager
   or vault.

2. **Tell SOPS to use it.** Add a rule to `.sops.yaml`, next to the `k3s-deployment` one (same indentation):

   ```yaml
   - path_regex: environments/<env>\-secrets\.yaml$
     age: '<public key>'
   ```

3. **Create the file from the k3s one** (needs the `k3s-deployment` age key):

   ```bash
   SOPS_AGE_KEY_FILE=~/k3s-deployment.agekey \
     sops -d environments/k3s-deployment-secrets.yaml > environments/<env>-secrets.yaml
   ```

   This file is **plain text**: do not commit it yet. Open it and give every
   password and token a new value. Keep the keys and structure as they are.

4. **Encrypt it with the new key**

   ```bash
   sops --encrypt --in-place environments/<env>-secrets.yaml
   SOPS_AGE_KEY_FILE=~/<env>.agekey sops -d environments/<env>-secrets.yaml > /dev/null && echo "decrypts OK"
   ```

5. **Remove the k3s copy** from the new branch:

   ```bash
   git rm environments/k3s-deployment-secrets.yaml
   ```

**Before committing:** `git diff --cached environments/<env>-secrets.yaml`
must show only `ENC[...]` values. If you see a plain password, stop and
encrypt (step 4).

Argo CD needs nothing extra: the tool loads the age key into the cluster on
every run (Part 1, Step 7).

## Step 3: Push and run

```bash
git add -A && git commit -m "feat(<env>): new k3s environment"
git push -u origin <env>
```

Then Part 1 with the new values: `secrets.ageKeyFile: ~/<env>.agekey` (Step 4),
and `env`, `branch`, `domain` in the config file (Step 5).
