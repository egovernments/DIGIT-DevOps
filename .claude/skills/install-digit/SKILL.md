---
name: install-digit
description: Install DIGIT 3 on a single-node k3s VM in any deployment shape (services | dev-bundle | domain-split), with optional Vault PII encryption, using the phase scripts in deploy-as-code/helm/charts/digit3/scripts. Use when asked to install or deploy DIGIT to a VM/cluster. Needs an SSH key for the VM, a domain pointing at it, a digit3 source checkout, and an image tag.
argument-hint: <ssh-key-path> <domain> [vm-user]
---

# Install DIGIT 3 on a k3s VM (any shape, optional Vault)

**Preferred path: one command.** `scripts/install.sh` orchestrates everything
below (flags or interactive prompts, Docker Hub preflight, per-phase resume
protocol) — collect the inputs in §1, then run it and monitor:

```bash
./install.sh --key <key> --domain <domain> --digit3 <path> \
  --shape single-container|domain-bundles|per-service --tag modulith-<sha> \
  --tenant "Name" --email <email> [--skip-vault]
```

Drive the individual phases yourself only when resuming a failed one or when
the user asks for step-by-step control.

You are driving the numbered, **idempotent** phase scripts in
`deploy-as-code/helm/charts/digit3/scripts/` (repo root = this repo). Run the
phases **straight through**, stopping only when a script fails. A completed
phase re-run converges to a no-op, so re-running after a fix is always safe.

## 1. Collect inputs

From the arguments: `$1` = SSH private-key path, `$2` = domain, `$3` =
optional VM user (default `azureuser`). Ask (AskUserQuestion) for anything
missing — do not guess:

- **ssh key / domain**: required, no defaults.
- **deployment shape**: `services` (16 pods), `dev-bundle` (one modulith
  JVM), or `domain-split` (4 bundle JVMs). Always ask; there is no default.
- **image tag**: the `modulith-<sha>` tag of the GitHub Actions builds — the
  normal path. Local `05-build.sh` (bundle shapes only) is the fallback when
  the user wants images from their working tree; then the tag is derived.
- **Vault**: ask whether PII encryption is wanted; if not, phase 04 is
  skipped and `VAULT_ENABLED` must be `"false"` in the shape's env blocks
  before deploying (check, don't assume).
- **digit3 repo path**: needed by phases 05–07. First search for an existing
  checkout (e.g. `find ~/Documents ~ -maxdepth 3 -name dev-bundle.package.yaml
  -path "*digit3*" 2>/dev/null`) and confirm the hit with the user. Only if
  none exists, offer to clone `-b modulith` beside this repo — clone only
  with explicit approval, never silently.
- **tenant name + admin email**: the install always ends by seeding and
  verifying a tenant; ask for both up front (tenant codes derive UPPERCASE
  from the name; the email must be unique).

## 2. Preflight (read-only — fix-or-stop before touching anything)

Check and report as a checklist:

- tools on PATH: `kubectl helm helmfile sops age age-keygen jq python3`
  (+ `python3 -c "import yaml"`); `docker` only if using 05-build.sh
- ssh key file exists; `ssh -o BatchMode=yes -o ConnectTimeout=10 -i <key>
  <vm-user>@<domain> true` succeeds
- `host <domain>` resolves
- digit3 checkout has `src/bundles/dev-bundle.package.yaml`
- the chosen tag exists on Docker Hub (spot-check one image:
  `https://hub.docker.com/v2/repositories/egovio/idgen/tags/<tag>`)

VM provisioning is **out of scope** — if ssh fails because the VM doesn't
exist, point the user at INSTALLATION-STEPS.md step 3 and stop.

## 3. Run the phases

From `deploy-as-code/helm/charts/digit3/scripts/`, in order, summarizing each
phase in one line as it completes:

```bash
./01-cluster.sh <ssh-key> <domain> [vm-user]     # k3s + tunnel + kubeconfig + .env
./02-secrets.sh                                  # age key, sops rule, secrets file
./03-backbone.sh                                 # backbone sync + keycloak DB AND role
./04-vault.sh                                    # OPTIONAL: init/unseal, transit+approle
./05-build.sh <digit3> [manifest]                # OPTIONAL: local bundle images + ctr import
./06-deploy.sh <digit3> <shape> [tag]            # chart gen, DIGIT_TAG sync, kong
./07-seed.sh "<tenant name>" <email> --verify    # tenant, runtime seeds, Vault verification
```

Timing: 03 (image pulls) and 05 (docker build) can take several minutes — use
long Bash timeouts or `run_in_background` with a wait loop; never abandon a
phase because it is slow. 02 prints a **BACK UP the age key** warning —
relay it to the user verbatim in your final report. Without Vault, run 07
without `--verify` (the verification is the Vault pipeline proof).

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
never `apply`; exactly one deployment shape at a time (the shapes publish the
same ingress paths and kong prefixes).

## 5. Wrap-up report

End with:

- the 07-seed PASS/FAIL verification table (API plaintext / `vault:v1:…` +
  HMAC in the DB / per-tenant transit key), or the seed summary without Vault
- `export KUBECONFIG=~/modulith-kubeconfig.yaml` for manual kubectl use
- the age-key backup warning
- ongoing ops: Vault pod restart → re-run `04-vault.sh` (it just unseals);
  VM reboot / kubectl timeouts → re-run `01-cluster.sh`; new images → re-run
  `06-deploy.sh <digit3> <shape> <new-tag>`; new tenant → `07-seed.sh`
