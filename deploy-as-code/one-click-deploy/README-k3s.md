# One-click deploy on k3s (single VM)

A step-by-step guide to set up a DIGIT environment on **k3s running on one
VM**. Follow the steps in order. Each step ends with a **Done when** check.

- **Runs on:** macOS (tested with k3s on an Azure VM)
- For EKS or AKS, or for setting up a new branch, see the main [README](README.md)

**Who does what**

| Who | Does | Step |
|---|---|---|
| Server owner | Gives you the server IP, SSH user and SSH key | [Step 0](#step-0-get-the-server-details) |
| Secrets owner | Gives you the age key | [Step 4](#step-4-get-the-age-key) |
| DNS admin | Points the domain at the VM | [Step 8](#step-8-verify-and-set-dns) |
| You (operator) | Everything else | Steps 1–8 |

**Contents**

- [Step 0: Get the server details](#step-0-get-the-server-details)
- [Step 1: Install the tools](#step-1-install-the-tools)
- [Step 2: Get the repository](#step-2-get-the-repository)
- [Step 3: Check SSH access to the VM](#step-3-check-ssh-access-to-the-vm)
- [Step 4: Get the age key](#step-4-get-the-age-key)
- [Step 5: Write the config file](#step-5-write-the-config-file)
- [Step 6: Check the cluster (read-only)](#step-6-check-the-cluster-read-only)
- [Step 7: Run the setup](#step-7-run-the-setup)
- [Step 8: Verify and set DNS](#step-8-verify-and-set-dns)
- [If something fails](#if-something-fails)
- [Start over on a clean VM](#start-over-on-a-clean-vm)

---

## Step 0: Get the server details

k3s must already be installed on the server. Get these from the server owner:

- the server's **public IP**
- the **SSH user** (e.g. `azureuser`)
- the **SSH private key** file

**Done when:** you have all three.

---

## Step 1: Install the tools

On your Mac (needs [Homebrew](https://brew.sh)):

```bash
brew install git go kubectl helm sops
```

`ssh` is already on macOS. Nothing else is needed.

**Done when:**

```bash
git --version && go version && kubectl version --client && helm version && sops --version
```

prints a version for each.

---

## Step 2: Get the repository

```bash
cd ~
git clone https://github.com/egovernments/DIGIT-DevOps.git
cd DIGIT-DevOps
git checkout k3s-deployment
git pull
```

Already cloned? Just `git checkout k3s-deployment && git pull`.

**Done when:** `git status` says *up to date with 'origin/k3s-deployment'*
and shows no changed files.

---

## Step 3: Check SSH access to the VM

Save the SSH private key from the server owner, e.g. as `~/.ssh/k3s-sandbox-key`.

```bash
chmod 600 ~/.ssh/k3s-sandbox-key
ssh -i ~/.ssh/k3s-sandbox-key <ssh user>@<VM IP> 'echo ok'
```

**Done when:** it prints `ok`.

---

## Step 4: Get the age key

The environment's secrets (`helm/environments/k3s-deployment-secrets.yaml`)
are encrypted with an **age key**. For `k3s-deployment` this is already set
up: you only need the **age private key file** from the secrets owner. They
send it securely (password manager / vault), never by email, chat or git.

Save it, e.g. as `~/k3s-deployment.agekey`, and check it opens the secrets:

```bash
chmod 600 ~/k3s-deployment.agekey
cd ~/DIGIT-DevOps/deploy-as-code/helm
SOPS_AGE_KEY_FILE=~/k3s-deployment.agekey \
  sops -d environments/k3s-deployment-secrets.yaml > /dev/null && echo "decrypts OK"
```

**Done when:** it prints `decrypts OK`.

> New environment (not `k3s-deployment`)? The secrets owner first creates a
> key and encrypts the file: see Step 4 in the main [README](README.md).

---

## Step 5: Write the config file

```bash
cd ~/DIGIT-DevOps/deploy-as-code/one-click-deploy
cp clusters/example-k3s.yaml clusters/<name>.yaml      # e.g. clusters/k3s-sandbox.yaml
```

Open `clusters/<name>.yaml` and replace every `<placeholder>`:

| Field | What to put | Example |
|---|---|---|
| `name` | Any name; shown when you confirm the cluster | `k3s-sandbox` |
| `env` | The environment | `k3s-deployment` |
| `branch` | The branch Argo CD deploys from | `k3s-deployment` |
| `domain` | The environment's domain | `k3s-deployment.digit.org` |
| `cluster.k3s.host` | Server public IP | from Step 0 |
| `cluster.k3s.sshUser` | SSH user | `azureuser` |
| `cluster.k3s.sshKeyFile` | Path to the SSH key | `~/.ssh/k3s-sandbox-key` |
| `secrets.ageKeyFile` | Path to the age key | `~/k3s-deployment.agekey` |

Leave everything else as it is (ports, namespaces, Kong services, timeouts).

This file stays on your computer; git ignores it.

**Done when:** no `<placeholder>` is left. (If one is, the tool stops at the
start and lists them.)

---

## Step 6: Check the cluster (read-only)

```bash
cd ~/DIGIT-DevOps/deploy-as-code/one-click-deploy
go run . status -f clusters/<name>.yaml
```

This changes nothing. It:

- connects to the VM over SSH and fetches the cluster's kubeconfig
- shows the node
- shows the Argo CD apps and platform apps (healthy or not)
- shows whether DNS points at the VM
- shows the Kong routes

On a new VM it says Argo CD is not installed. That is expected.

**Done when:** it connects and lists the node.

---

## Step 7: Run the setup

```bash
go run . all -f clusters/<name>.yaml
```

What happens, in order:

1. Shows the cluster and its node and asks *"Is "<name>" the right cluster?"*
2. Checks you are cluster-admin, your branch matches GitHub, and the age key opens the secrets
3. Loads the age key into the cluster, so Argo CD can open the secrets too
4. Asks *"Run the deployer now?"* → installs Argo CD
5. Asks *"Apply the bootstrap now?"* → Argo CD starts deploying from GitHub
6. Shows a table of the platform apps until all are healthy (up to 20 minutes, a progress line every minute):
   ingress-nginx, cert-manager, Elasticsearch, Kafka, Postgres, Keycloak, Kong
7. Checks DNS (a warning only)
8. Asks before configuring Kong, then prints a summary

Good to know:

- Nothing changes in the cluster until the checks (2) pass
- Answering "no" to any question stops the run
- It never deletes anything; safe to rerun

**Done when:** it prints `Done.`

---

## Step 8: Verify and set DNS

1. Check every app is Synced and Healthy:

   ```bash
   go run . status -f clusters/<name>.yaml
   ```

2. If DNS shows a warning, ask the DNS admin for an **A record**:
   `<domain>` → `<VM IP>`.
   The HTTPS certificate is issued automatically once DNS points at the VM.

3. Open `https://<domain>` in a browser.

**After this:** changes to the environment are made in git: push to
`k3s-deployment` and Argo CD applies them. Run the tool again only to
reconfigure Kong:

```bash
go run . kong -f clusters/<name>.yaml
```

---

## If something fails

Every failure says what failed and what to do next (`Next:`). Fix it and run
the same command again.

| Message | What to do |
|---|---|
| `config file ... is not complete` | Fill in every field it lists |
| `reading k3s.yaml over SSH` failed | Run the Step 3 check; port 22 must be open to you |
| `cannot reach the API server` | Ask the server owner: port 6443 open to you, and k3s installed with `--tls-san <server IP>` |
| `local ... differs from origin` | `git pull` (Step 2) |
| `cannot decrypt ... with age` | Wrong age key; run the Step 4 check |
| Platform apps timed out | Run `status` to see which app; fix it in git and push, then `go run . backbone -f clusters/<name>.yaml` |
| An Elasticsearch pod keeps restarting | Ask the server owner to set `vm.max_map_count=262144` on the server |
| No HTTPS certificate | DNS record (Step 8) and ports 80/443 open to everyone |
| Kong step failed | `go run . kong -f clusters/<name>.yaml` |

Rerun only one part:

| Command | Runs |
|---|---|
| `go run . argocd -f clusters/<name>.yaml` | Checks, Argo CD install and bootstrap |
| `go run . backbone -f clusters/<name>.yaml` | Waits for the platform apps |
| `go run . kong -f clusters/<name>.yaml` | Configures Kong |

Avoid: two runs at once, fixing things by hand in the cluster (Argo CD puts
back what is in git), and running with unpushed changes.

---

## Start over on a clean VM

The tool never deletes anything. To start from scratch, ask the server owner
to reinstall k3s (this deletes everything in the cluster), then run Step 6
and Step 7 again.
