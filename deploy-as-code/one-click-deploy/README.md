# One-click deploy

Sets up a DIGIT environment on Kubernetes from one YAML config file.

- **Platforms:** k3s on a VM, Amazon EKS, Azure AKS
- **Tested:** k3s only, ran on macOS. EKS, AKS, Linux and Windows (WSL2) are not yet tested

## How to use this guide

- **k3s on a single VM?** Use the shorter k3s-only guide: [README-k3s.md](README-k3s.md).
- **Setting up an environment?** Follow [Part 1](#part-1-set-up-an-environment) from Step 1 to Step 8, in order.
- **Setting up a new branch / environment for the first time?** Do [Part 2](#part-2-set-it-up-on-another-branch) first, then Part 1.

**Who does what**

| Who | Does | Step |
|---|---|---|
| Operator (you) | Installs tools, writes the config file, runs the tool | All steps |
| Cluster admin (EKS, AKS only) | Gives you cluster-admin access | [Step 3](#step-3-get-cluster-access) |
| Secrets owner | Prepares the encrypted secrets and gives you and Argo CD access | [Step 4](#step-4-make-sure-the-secrets-are-ready) |

**Contents**

- [Part 1: Set up an environment](#part-1-set-up-an-environment)
  - [Step 1: Install the tools](#step-1-install-the-tools)
  - [Step 2: Get the repository](#step-2-get-the-repository)
  - [Step 3: Get cluster access](#step-3-get-cluster-access)
  - [Step 4: Make sure the secrets are ready](#step-4-make-sure-the-secrets-are-ready)
  - [Step 5: Write the config file](#step-5-write-the-config-file)
  - [Step 6: Check the cluster (read-only)](#step-6-check-the-cluster-read-only)
  - [Step 7: Run the setup](#step-7-run-the-setup)
  - [Step 8: Verify and set DNS](#step-8-verify-and-set-dns)
  - [If something fails](#if-something-fails)
- [Part 2: Set it up on another branch](#part-2-set-it-up-on-another-branch)
  - [2.1 Files the branch needs](#21-files-the-branch-needs)
  - [2.2 Differences by cluster type](#22-differences-by-cluster-type)
  - [2.3 Test the branch before merging](#23-test-the-branch-before-merging)

---

## Part 1: Set up an environment

### Step 1: Install the tools

| Your computer | Supported |
|---|---|
| macOS (Intel or Apple silicon) | Yes (tested) |
| Linux (Ubuntu, Debian, RHEL, …) | Yes (not yet tested) |
| Windows 10/11 | Yes (not yet tested), **through WSL2**: run `wsl --install -d Ubuntu` in an admin PowerShell, then follow the Linux steps inside Ubuntu. Keep the repo and keys under `~/`, not `/mnt/c/` |
| Windows without WSL2 | No |

Any of these can set up any cluster type.

**Install the tools**

Everyone needs:

| Tool | Version |
|---|---|
| `git` | any |
| `go` | 1.22 or later |
| `kubectl` | within one minor version of the cluster |
| `helm` | 3.x |
| `sops` | 3.8 or later |

Plus, only for your cluster type:

| Cluster type | Extra tool | Why |
|---|---|---|
| k3s on a VM | `ssh` (already on macOS and Linux) | To log in to the VM and fetch the cluster's kubeconfig |
| EKS | `aws` (AWS CLI v2) | To log in to AWS and get the cluster's kubeconfig |
| AKS | `az` (Azure CLI) and `kubelogin` | To log in to Azure and get the cluster's kubeconfig |

macOS:

```bash
brew install git go kubectl helm sops               # everyone
                                                    # k3s: nothing extra (ssh is built in)
brew install awscli                                 # EKS only
brew install azure-cli Azure/kubelogin/kubelogin    # AKS only
```

Linux / WSL2:

```bash
sudo apt-get update && sudo apt-get install -y git openssh-client curl unzip
# Go:      https://go.dev/doc/install (the apt package is often too old)
# kubectl: https://kubernetes.io/docs/tasks/tools/install-kubectl-linux/
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# sops:    linux binary from https://github.com/getsops/sops/releases into /usr/local/bin
# k3s:     nothing extra (ssh comes from openssh-client above)
# EKS only: AWS CLI v2 from https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html
# AKS only: curl -sL https://aka.ms/InstallAzureCLIDeb | sudo bash && sudo az aks install-cli
```

**Done when:** `git --version && go version && kubectl version --client && helm version && sops --version` all print a version.

### Step 2: Get the repository

```bash
cd ~
git clone https://github.com/egovernments/DIGIT-DevOps.git
cd DIGIT-DevOps
git checkout <branch>        # e.g. k3s-deployment
git pull
```

Already cloned? Just `git checkout <branch> && git pull`.

**Done when:** `git status` says your branch is up to date with `origin/<branch>`, with no local changes.

### Step 3: Get cluster access

Follow the part for your cluster type.

#### k3s on a VM

| You need | Who provides it |
|---|---|
| The VM's static public IP, SSH user and private SSH key | VM owner |
| Ports 22 and 6443 open to your IP; 80 and 443 open to everyone | VM owner |
| k3s installed with `--disable traefik --tls-san <public IP>` | VM owner |
| DNS **A record**: domain → VM public IP | DNS admin |

Check from your computer:

```bash
chmod 600 <ssh key>
ssh -i <ssh key> <user>@<ip> 'echo ok'
```

#### Amazon EKS

Done once by the **AWS / cluster admin**:

1. Give the operator an AWS identity (SSO user or an IAM role) allowed to
   `eks:DescribeCluster` and `eks:ListClusters`.
2. Make that identity cluster-admin:

   ```bash
   aws eks create-access-entry --cluster-name <cluster> --region <region> \
     --principal-arn <operator role ARN>
   aws eks associate-access-policy --cluster-name <cluster> --region <region> \
     --principal-arn <operator role ARN> \
     --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy \
     --access-scope type=cluster
   ```

3. The cluster has the EBS CSI driver (storage class `gp3`) and its API
   endpoint is reachable from the operator's network.
4. After the first run: a DNS **CNAME** domain → load balancer hostname (the
   tool prints it).

Check from your computer:

```bash
aws sso login --profile <profile>
aws sts get-caller-identity --profile <profile>
aws eks describe-cluster --name <cluster> --region <region> --profile <profile> --query cluster.status
```

#### Azure AKS

Done once by the **subscription / cluster admin**:

1. Give the operator two roles on the AKS cluster:

   ```bash
   AKS_ID=$(az aks show -g <rg> -n <cluster> --query id -o tsv)
   az role assignment create --assignee <operator email> \
     --role "Azure Kubernetes Service Cluster User Role" --scope $AKS_ID
   az role assignment create --assignee <operator email> \
     --role "Azure Kubernetes Service RBAC Cluster Admin" --scope $AKS_ID
   ```

   (Clusters with Kubernetes RBAC instead of Azure RBAC: a `ClusterRoleBinding`
   to `cluster-admin` for the operator.)
2. The cluster has the `managed-csi` storage class and its API server is
   reachable from the operator's IP.
3. After the first run: a DNS **A record** domain → load balancer IP (the
   tool prints it).

Check from your computer:

```bash
az login
az account set --subscription <subscription id>
az aks show -g <rg> -n <cluster> --query provisioningState -o tsv
```

**Done when:** the check commands above work.

### Step 4: Make sure the secrets are ready

The secrets owner does this once per environment. **Already set up for `k3s-deployment`: skip to Step 5** (you only need the age key file from the secrets owner).

The environment's secrets file (`helm/environments/<env>-secrets.yaml`) is
encrypted with SOPS. Before the first run, the secrets owner makes sure both
the **operator** (on their computer) and **Argo CD** (in the cluster) can
decrypt it. Secret values and private keys never go into git, email or chat.

**Steps (all cluster types)**

1. Create the key (see the table below).
2. Add a rule to `deploy-as-code/helm/.sops.yaml`:

   ```yaml
   - path_regex: environments/<env>\-secrets\.yaml$
     age: '<age public key>'           # k3s
     # kms: '<KMS key ARN>'            # EKS
     # azure_keyvault: '<key URL>'     # AKS
   ```

3. Encrypt the file and commit only the encrypted version:

   ```bash
   cd deploy-as-code/helm
   sops --encrypt --in-place environments/<env>-secrets.yaml                 # first time
   sops environments/<env>-secrets.yaml                                      # later edits
   sops -d environments/<env>-secrets.yaml > /dev/null && echo "decrypts OK"  # check
   ```

4. Give access to the operator and to Argo CD (table below), then push.

| | k3s on a VM | EKS | AKS |
|---|---|---|---|
| Key | age key | AWS KMS key | Azure Key Vault RSA key |
| Create it | `age-keygen -o <env>.agekey` (prints the public key) | `aws kms create-key --description "<env> SOPS"` | `az keyvault key create --vault-name <vault> --name sops-key --kty RSA` |
| Operator access | Send the private key file securely (password manager / vault) | `kms:Decrypt` on the key | **Key Vault Crypto User** on the vault |
| Argo CD access | Nothing to do: the tool loads the operator's key into the cluster | An IAM role for `argocd:argocd-repo-server` with `kms:Decrypt` (via the cluster's OIDC provider); its ARN goes in `AWS_ROLE_ARN` in `helm/charts/backbone-services/argo-cd/values.yaml` | A managed identity with Key Vault Crypto User, federated to `argocd:argocd-repo-server`; its client ID goes in `argo-cd-values.yaml` (see [2.2](#22-differences-by-cluster-type)) |

Then tell the operator it is done and which method to use (`age`, `kms` or
`azure_kv`). The tool checks all of this again before changing anything.

To change a secret later: `sops environments/<env>-secrets.yaml`, save, push.
Argo CD picks it up; no need to run the tool again.

**Done when:** the secrets owner confirms it is done and tells you the method (`age`, `kms` or `azure_kv`). For k3s, you have the age key file on your computer (`chmod 600` it).

### Step 5: Write the config file

The config file is the tool's only input. Every field must be filled; if
anything is missing or still a `<placeholder>`, the run stops at the start
and lists every problem.

Copy the template for your cluster type and replace every `<placeholder>`.
The standard DIGIT values (namespaces, Kong services, timeouts) are already
filled in.

```bash
cd ~/DIGIT-DevOps/deploy-as-code/one-click-deploy
cp clusters/example-k3s.yaml clusters/<name>.yaml     # or example-eks.yaml / example-aks.yaml
```

Your `clusters/<name>.yaml` stays on your computer: only the `example-*`
templates are committed.

| Field | k3s | EKS | AKS | What to put |
|---|---|---|---|---|
| `name` | yes | yes | yes | Any name; shown when you confirm the cluster |
| `env` | yes | yes | yes | The environment, e.g. `k3s-deployment` |
| `branch` | yes | yes | yes | The git branch Argo CD deploys from |
| `domain` | yes | yes | yes | The environment's public domain |
| `cluster.k3s.host`, `sshUser`, `sshKeyFile` | yes | | | VM IP, SSH user, path to the SSH key |
| `secrets.ageKeyFile` | yes | | | Path to the age key |
| `cluster.eks.name`, `region`, `profile` | | yes | | Cluster name, region, AWS CLI profile |
| `cluster.eks.roleArn` | | optional | | Only if access is through an assumed role |
| `secrets.awsProfile` | | yes | | AWS profile with `kms:Decrypt` (often the same) |
| `cluster.aks.name`, `resourceGroup`, `subscription` | | | yes | From `az aks list -o table` |

Two options:

- `options.assumeYes: true` answers yes to every question except the cluster
  confirmation, which is always asked.
- `options.skipGitCheck: true` allows a local checkout that differs from
  GitHub. Testing only.

**Done when:** you have `clusters/<name>.yaml` with no `<placeholder>` left.

### Step 6: Check the cluster (read-only)

```bash
cd ~/DIGIT-DevOps/deploy-as-code/one-click-deploy
go run . status -f clusters/<name>.yaml
```

This changes nothing. It:

- connects to the cluster and shows its nodes
- shows the nodes, Argo CD apps and platform apps (healthy or not)
- shows whether your domain points at the cluster:
  - k3s: compares the domain with the VM's IP
  - EKS / AKS: compares the domain with the load balancer's address. On a new cluster the load balancer does not exist yet, so it says *"Skipping the DNS check"*. That is expected
- shows the Kong routes

On a new cluster it reports that Argo CD is not installed. That is expected.

**Done when:** it connects and lists the cluster's nodes. If not, see [If something fails](#if-something-fails).

### Step 7: Run the setup

```bash
go run . all -f clusters/<name>.yaml
```

What happens, in order:

1. Shows the cluster and its nodes and asks *"Is "<name>" the right cluster?"*
2. Checks you are cluster-admin, the branch matches GitHub, and the secrets decrypt
3. Asks *"Run the deployer now?"* → installs Argo CD
4. Asks *"Apply the bootstrap now?"* → Argo CD starts deploying from GitHub
5. Shows a table of the platform apps until all are healthy (up to 20 minutes, a progress line every minute)
6. Checks DNS (a warning only, never stops the run). If the domain does not point at the cluster yet, it prints the exact record to ask for:
   - k3s: *"Ask the DNS admin for an A record `<domain>` -> `<VM IP>`"*
   - EKS: *"Ask the DNS admin for a CNAME record `<domain>` -> `<xxxx.elb.amazonaws.com>`"*
   - AKS: *"Ask the DNS admin for an A record `<domain>` -> `<load balancer IP>`"*
7. Asks before configuring Kong, then prints a summary

Good to know:

- Nothing changes in the cluster until the checks (2) pass
- Answering "no" to any question stops the run
- It never deletes anything; safe to rerun

**Done when:** it prints `Done.`

### Step 8: Verify and set DNS

1. Run `status` again and check every app is Synced and Healthy:

   ```bash
   go run . status -f clusters/<name>.yaml
   ```

2. If the DNS line is a warning, ask the DNS admin for the record it shows:

   | Cluster | Record | Points to |
   |---|---|---|
   | k3s | A | The VM's public IP (known before the run) |
   | EKS | CNAME | The load balancer hostname, e.g. `xxxx.elb.amazonaws.com` (known only after Step 7) |
   | AKS | A | The load balancer IP (known only after Step 7) |

   On EKS and AKS the cloud creates the load balancer during Step 7, so the
   DNS record can only be requested after the run. That is normal.

   Once DNS is set, run `status` again: the DNS line should say the domain
   *"resolves to ..., which is the ingress load balancer"* (EKS / AKS) or
   the VM (k3s). The HTTPS certificate is then issued automatically.

3. Open `https://<domain>` in a browser.

**After this:** changes to the environment are made in git: push to the branch and Argo CD applies them. Run the tool again only to reconfigure Kong (`go run . kong -f clusters/<name>.yaml`).

Other commands, if you need to rerun one part:

| Command | Runs |
|---|---|
| `go run . argocd -f clusters/<name>.yaml` | Only the checks, Argo CD install and bootstrap |
| `go run . backbone -f clusters/<name>.yaml` | Only waits for the platform apps |
| `go run . kong -f clusters/<name>.yaml` | Only configures Kong |

### If something fails


Every failure says what failed and what to do next (`Next:`). Fix it and run
the same command again.

| Failed at | What to do |
|---|---|
| Checks at the start | Nothing was changed. Fix what it reports and rerun |
| Argo CD install or bootstrap | Rerun `all` (or `argocd`) |
| Waiting for platform apps (timed out) | Fix the app in git and push, then run `backbone` |
| Kong | Run `kong` |

Common messages:

| Message | What to do |
|---|---|
| `config file ... is not complete` | Fill in every field it lists |
| `cannot reach the API server` (k3s) | Port 6443 open to you; k3s started with `--tls-san <IP>` |
| `no valid AWS credentials` | `aws sso login --profile <profile>` |
| `not logged in to Azure` | `az login` |
| `this identity is not cluster-admin` | Ask the cluster admin ([Step 3](#step-3-get-cluster-access)) |
| `local ... differs from origin` | `git pull`, or push your changes |
| `cannot decrypt ...` | Your key or identity has no access to the secrets key ([Step 4](#step-4-make-sure-the-secrets-are-ready)) |
| `secrets.method is ..., but the file is encrypted with ...` | Set `secrets.method` to how the file is actually encrypted |
| `does not mount the sops-age Secret` / `set no AWS role` / `no Workload Identity` | Argo CD's decrypt access is not set up on the branch ([2.2](#22-differences-by-cluster-type)) |
| `ApplicationSet ... does not exist` | The branch is not pushed yet, or Argo CD has not synced it |
| No HTTPS certificate | Check DNS (`status`) and that ports 80/443 are open |
| `Service egov/kong-kong-admin not found` | Kong is not deployed yet; run `all` first |

Avoid: two runs against the same cluster at once, fixing things by hand in
the cluster (Argo CD puts back what is in git), and running with unpushed
changes.

---

## Part 2: Set it up on another branch

To use the tool for a new environment `<env>` on branch `<branch>`, the branch
needs the files below. Copy them from `k3s-deployment` (the reference branch)
and rename `k3s-deployment` to `<env>` inside them. Paths are under
`deploy-as-code/`.

### 2.1 Files the branch needs

| File | What to do |
|---|---|
| `one-click-deploy/` | Copy the whole folder |
| `helm/environments/<env>.yaml` | The environment's values. Set the storage class for the cluster type (`local-path` on k3s, `gp3` on EKS, `managed-csi` on AKS). It must include `keycloak` in the cluster-configs namespaces and `db.namespace: [ egov, health, keycloak ]` in the cluster-configs secrets |
| `helm/environments/<env>-secrets.yaml` | The secrets, encrypted ([Step 4](#step-4-make-sure-the-secrets-are-ready)) |
| `helm/.sops.yaml` | A rule for `<env>-secrets.yaml` ([Step 4](#step-4-make-sure-the-secrets-are-ready)) |
| `helm/charts/argo-cd/bootstrap/<env>-bootstrap.yaml` | Copy `k3s-deployment-bootstrap.yaml`; set the name to `<env>-bootstrap` and `targetRevision` to `<branch>` |
| `helm/charts/argo-cd/backbone/backbone-app-project.yaml` | Copy unchanged |
| `helm/charts/argo-cd/backbone/<env>-backbone-appset.yaml` | Copy `k3s-deployment-backbone-appset.yaml`; set the name, `targetRevision: <branch>`, and the value file names to `<env>` |
| `helm/environments/<env>-backbone/` | Copy `k3s-deployment-backbone/` (one file per backbone chart; adjust per [2.2](#22-differences-by-cluster-type)) |
| `helm/charts/argo-cd/egov/<env>-egov-appset-*.yaml` | The DIGIT appsets, including `-platform` (Postgres, Keycloak, Kong); set the name, `targetRevision: <branch>` and value file `<env>.yaml` |
| `helm/charts/argo-cd/egov/egov-app-project.yaml` | Must allow both the `egov` and `keycloak` namespaces |
| `helm/charts/core-services/gateway-kong/values.yaml` | Kong in database mode with the DIGIT image (as on `k3s-deployment`). Or set `kong.enabled: false` in the config to skip Kong |

If the branch already has its own platform appsets under other names, keep
them and list their names under `waitFor.appSets` in the config file.

### 2.2 Differences by cluster type

| | k3s on a VM | EKS | AKS |
|---|---|---|---|
| `helm/charts/backbone-services/argo-cd/argo-cd-values.yaml` | Copy from `k3s-deployment` | Must **not** exist | Copy `values-azure-keyvault-sops.yaml` to this name and set the managed identity's client ID and tenant ID |
| Argo CD decrypt access | Nothing extra | IAM role ARN in `AWS_ROLE_ARN` in `argo-cd/values.yaml` | The managed identity above |
| `<env>-backbone/elasticsearch-*.yaml` | Keep (1 replica, `local-path`) | Remove the single-node settings; storage class `gp3` | Same as EKS with `managed-csi` |
| `<env>-backbone/kafka-kraft.yaml` | Keep | Keep `fullnameOverride: release-name-kafka`; remove the single-node settings; set the storage class | Same as EKS |
| `<env>-backbone/cert-manager.yaml`, `ingress-nginx.yaml` | Keep | Keep | Keep |
| DNS record | A → VM IP | CNAME → load balancer hostname | A → load balancer IP |
| Config `secrets.method` | `age` | `kms` | `azure_kv` |

### 2.3 Test the branch before merging

Argo CD always deploys from GitHub, from the branch named in `targetRevision`.
To test a feature branch before it is merged into `<branch>`:

```bash
# 1. Commit your changes on the feature branch
git add <changed paths>
git commit -m "<message>"

# 2. Point Argo CD at the feature branch, as a separate temporary commit
grep -rl 'targetRevision: <branch>$' deploy-as-code/helm/charts/argo-cd \
  | xargs sed -i '' 's/targetRevision: <branch>$/targetRevision: <feature-branch>/'   # Linux: sed -i
git commit -am "TEMP: point Argo CD at <feature-branch> for testing"

# 3. Push
git push -u origin <feature-branch>
```

Set `branch: <feature-branch>` in your config file and run `status`, then
`all`.

Before raising the PR, undo the temporary commit:

```bash
git log --oneline -3          # find the TEMP commit
git revert <TEMP commit sha>
git push
```

After the PR is merged: check out `<branch>`, `git pull`, set
`branch: <branch>` in the config file and run `go run . argocd -f clusters/<name>.yaml`,
so the cluster follows `<branch>` again. Then delete the feature branch.
