---
name: install-digit
description: Install DIGIT 3 with Vault PII encryption on a single-node k3s VM using the phase scripts in deploy-as-code/helm/charts/digit3/scripts, in one of three shapes (single-container default, domain-bundles, per-service). Use when asked to install or deploy DIGIT to a VM/cluster. Needs an SSH key for the VM, a domain pointing at it, and a digit3 source checkout.
argument-hint: <ssh-key-path> <domain> [vm-user]
---

# Install DIGIT 3 (+ Vault) on a k3s VM — single-container / domain-bundles / per-service

You are driving the numbered, **idempotent** phase scripts in
`deploy-as-code/helm/charts/digit3/scripts/` (repo root = this repo). Run the
phases **straight through**, stopping only when a script fails. A completed
phase re-run converges to a no-op, so re-running after a fix is always safe.

## 1. Collect inputs

From the arguments: `$1` = SSH private-key path, `$2` = domain, `$3` =
optional VM user (default `azureuser`). Ask (AskUserQuestion) for anything
missing — do not guess:

- **ssh key / domain**: required, no defaults.
- **shape**: ALWAYS ask which deployment shape to install (AskUserQuestion),
  unless the user already named one in their request. Options to present:
  - `single-container` (recommended default) — all 16 services in one JVM,
    ~0.5 GB, 1 pod
  - `domain-bundles` — 4 JVMs along building-block lines (identity /
    notification / billing / admin), independent scaling per group
  - `per-service` — every service its own pod (16 pods, ~5 GB), the classic
    microservice layout
  Pass the choice as `--shape <shape>` to 05 and 06 (07 reads it from
  `scripts/.env`).
- **digit3 repo path**: needed by phases 05–06. First search for an existing
  checkout (e.g. `find ~/Documents -maxdepth 3 -name dev-bundle.package.yaml
  -path "*digit3*"`) and confirm the hit with the user. Only if none exists,
  offer to run `git clone -b modulith https://github.com/digitnxt/digit3.git`
  beside this repo — clone only with explicit approval, never silently.
- **tenant name + admin email**: the install always ends by seeding and
  verifying a tenant; ask for both up front (tenant codes derive UPPERCASE
  from the name; the email must be real enough to be unique).

## 2. Preflight (read-only — fix-or-stop before touching anything)

Check and report as a checklist:

- tools on PATH: `kubectl helm helmfile sops age age-keygen jq docker python3`
  (+ `python3 -c "import yaml"`), `java -version` = 25, `mvn -version` ≥ 3.9
- ssh key file exists; `ssh -o BatchMode=yes -o ConnectTimeout=10 -i <key>
  <vm-user>@<domain> true` succeeds
- `host <domain>` resolves
- docker daemon running (`docker info -f '{{.ServerVersion}}'`)
- digit3 checkout has `src/bundles/dev-bundle.package.yaml`

VM provisioning is **out of scope** — if ssh fails because the VM doesn't
exist, point the user at INSTALLATION-STEPS.md step 3 and stop.

## 3. Run the phases

From `deploy-as-code/helm/charts/digit3/scripts/`, in order, summarizing each
phase in one line as it completes:

```bash
./01-cluster.sh <ssh-key> <domain> [vm-user]   # k3s + tunnel + kubeconfig + .env
./02-secrets.sh                                # age key, sops rule, secrets file (fresh random passwords), domain stamp
./03-backbone.sh                               # backbone sync + keycloak DB AND role
./04-vault.sh                                  # init/unseal, transit+approle, creds into sops
./05-build.sh [--shape <shape>] <digit3-path>  # Docker-Hub-first: verifies published pins, builds only what's missing
./06-deploy.sh [--shape <shape>] <digit3-path> # chart gen + service-host map from manifest, db, tag pin, shape helmfile sync, kong
./07-seed.sh "<tenant name>" <email> --verify  # tenant, idgen template, Vault verification
```

Timing: 03 and 05 can take several minutes (image pulls / docker build) — use
long Bash timeouts or `run_in_background` with a wait loop; never abandon a
phase because it is slow. 02 prints a **BACK UP the age key** warning —
relay it to the user verbatim in your final report.

## 4. On failure

Do not retry blindly and do not improvise cluster surgery:

1. Read the actual error from the script output (and `kubectl get pods
   -n egov`, pod logs) — then look it up in the **gotchas table** at the end
   of `deploy-as-code/helm/charts/digit3/INSTALL.md`. Nearly every known
   failure mode is mapped to its fix there. Most common transient: kubectl
   suddenly failing with `TLS handshake timeout` or `connection refused
   127.0.0.1:16443` mid-phase means the SSH tunnel dropped — re-run
   `./01-cluster.sh <key> <domain>` and then the interrupted script.
2. Apply the mapped fix, then **re-run the same script** — idempotence makes
   this safe.
3. If the symptom is not in the table, stop and report to the user with the
   error, the phase, and your best diagnosis.

Standing rules: never print secret values (the scripts already keep them off
screen — keep it that way in any ad-hoc debugging); always helmfile `sync`,
never `apply`; exactly one deployment shape at a time.

## 5. Wrap-up report

End with:

- the tenant admin credentials 07-seed printed (shown once — tell the user to
  store them), and how to call APIs through Kong: `./08-token.sh <TENANT>
  <email>` mints a gateway-ready bearer token (see INSTALL.md §7 for why
  issuer/client matter)
- the 07-seed PASS/FAIL verification table (API plaintext / `vault:v1:…` +
  HMAC in the DB / per-tenant transit key)
- `export KUBECONFIG=~/modulith-kubeconfig.yaml` for manual kubectl use
- the age-key backup warning
- ongoing ops: Vault pod restart → re-run `04-vault.sh` (it just unseals);
  VM reboot / kubectl timeouts → re-run `01-cluster.sh`; new build → re-run
  `05-build.sh` + `06-deploy.sh`; new tenant → `07-seed.sh`
- note that `environments/azure-k3s.yaml` and the new (encrypted)
  `environments/azure-k3s-secrets.yaml` were modified/created locally —
  **offer** to commit them, never commit or push without being asked
