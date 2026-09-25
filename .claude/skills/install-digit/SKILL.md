---
name: install-digit
description: Install DIGIT 3 on a single-node k3s VM in any deployment shape (single-container | domain-bundles | per-service), with Vault PII encryption on by default, using the phase scripts in deploy-as-code/helm/charts/digit3/scripts. Use when asked to install or deploy DIGIT to a VM/cluster. Needs an SSH key for the VM, a domain pointing at it, a digit3 source checkout, an image tag, and (recommended) Docker Hub credentials for authenticated pulls.
argument-hint: <ssh-key-path> <domain> [vm-user]
---

# Install DIGIT 3 on a k3s VM (any shape; Vault on by default)

**Preferred path: one command.** `scripts/install.sh` orchestrates everything
below (flags or interactive prompts, Docker Hub preflight, per-phase resume
protocol) — collect the inputs in §1, then run it and monitor:

```bash
cd deploy-as-code/helm/charts/digit3/scripts
./install.sh --key <key> --domain <domain> [--vm-user <user>] --digit3 <path> \
  --shape single-container|domain-bundles|per-service --tag modulith-<sha> \
  --tenant "Name" --email <email> [--skip-vault]
# Docker Hub creds: lib.sh sources ~/.config/digit3/dockerhub.env (DOCKERHUB_USER=/DOCKERHUB_TOKEN=) or the
# env vars by itself — pass --hub-user/--hub-token only when neither exists (the flag is visible in `ps`).
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
- **deployment shape**: `single-container` (all 16 services in one JVM),
  `domain-bundles` (4 bundle JVMs), or `per-service` (16 pods). Always ask —
  do not pick one for the user (install.sh's interactive menu marks
  `single-container` as recommended; that is a hint for humans, not a default
  for you). The pre-rename names `dev-bundle` / `domain-split` /
  `services` are accepted as synonyms if the user says them.
- **image tag**: the `modulith-<sha>` tag of the GitHub Actions builds — the
  normal path. Local `05-build.sh` (bundle shapes only) is the fallback when
  the user wants images from their working tree; then the tag is derived.
- **Docker Hub credentials** (recommended): a Docker Hub username and a
  read-only access token — any account works, the `egovio/*` images are
  public. Without them the VM pulls anonymously, capped at 100/h per IP; a
  per-service install needs 42 images, so a repeat within the hour fails with
  429. Check for `DOCKERHUB_USER`/`DOCKERHUB_TOKEN` in the environment or
  `~/.config/digit3/dockerhub.env` (`KEY=value` lines) — `lib.sh` sources
  them automatically, no flags needed. Pass `--hub-user/--hub-token` only
  when neither exists (a token on the command line is visible in `ps` for the
  whole install); never echo the token.
- **Vault**: on by default (the shipped env blocks have `vault-enabled` /
  `VAULT_ENABLED` true). Only if the user explicitly declines PII encryption:
  `--skip-vault`, and `VAULT_ENABLED` must be `"false"` in the shape's env
  blocks before deploying (check, don't assume) — otherwise otp/individual
  crash-loop.
- **digit3 repo path**: needed by phases 05–07. First search for an existing
  checkout (e.g. `find ~/Documents ~ -maxdepth 4 -name dev-bundle.package.yaml
  -path "*digit3*" 2>/dev/null` — the file sits at
  `<checkout>/src/bundles/`, four levels below `~` for a checkout in `~`) and confirm the hit with the user. Only if
  none exists, offer to clone `-b modulith` beside this repo — clone only
  with explicit approval, never silently.
- **tenant name + admin email**: the install always ends by seeding and
  verifying a tenant; ask for both up front (the tenant code is the name
  UPPERCASED with spaces removed — `"Skill Guntur"` → `SKILLGUNTUR`; the
  email must be unique).
- **age key / secrets file**: `02-secrets.sh` reuses `~/.config/sops/age/keys.txt`
  if it exists (one key shared by every environment installed from this
  workstation) and writes a per-domain secrets file
  `environments/azure-k3s-secrets.<domain>.yaml`; neither needs input.

## 2. Preflight (read-only — fix-or-stop before touching anything)

Check and report as a checklist:

- tools on PATH: `kubectl helm helmfile sops age age-keygen jq python3`
  (+ `python3 -c "import yaml"`); `docker` only if using 05-build.sh
- ssh key file exists; `ssh -o BatchMode=yes -o ConnectTimeout=10 -i <key>
  <vm-user>@<domain> true` succeeds
- `host <domain>` resolves
- digit3 checkout has `src/bundles/dev-bundle.package.yaml`
- the chosen tag exists on Docker Hub — spot-check the **shape's** image
  (bundle builds publish no per-service images, so `idgen` 404s for a
  bundle-only tag): `dev-bundle` for single-container, `identity-bundle` for
  domain-bundles, `idgen` for per-service —
  `https://hub.docker.com/v2/repositories/egovio/<image>/tags/<tag>`.
  `install.sh` preflights the shape's full image set (with `-db` pairs) itself.
- Docker Hub credentials available (flags, `DOCKERHUB_USER`/`DOCKERHUB_TOKEN`, or
  `~/.config/digit3/dockerhub.env`) — if not, warn that pulls are anonymous (100/h per IP)

VM provisioning is **out of scope** — if ssh fails because the VM doesn't
exist, point the user at INSTALLATION-STEPS.md step 3 and stop.

## 3. Run the phases

From `deploy-as-code/helm/charts/digit3/scripts/`, in order, summarizing each
phase in one line as it completes:

```bash
./01-cluster.sh <ssh-key> <domain> [vm-user]     # k3s + tunnel + kubeconfig + .env
./02-secrets.sh                                  # age key, sops rule, secrets file
./03-backbone.sh                                 # backbone sync + keycloak DB AND role
./04-vault.sh                                    # init/unseal, transit+approle (omit only with --skip-vault)
./05-build.sh <digit3> [manifest]                # OPTIONAL: local bundle images + ctr import
./06-deploy.sh <digit3> <shape> [tag]            # chart gen, DIGIT_TAG sync, kong
./07-seed.sh "<tenant name>" <email> --verify    # tenant, runtime seeds, Vault verification
```

Timing: 03 (backbone), 06 (image pulls + rollouts — the longest phase for
per-service) and 07 (Keycloak readiness + the 15-service migration fan-out)
each take several minutes; 05 (docker build) too when used. Use long Bash
timeouts or `run_in_background` with a wait loop; never abandon a phase
because it is slow. Expected noise: 03 prints `cert-manager webhook not
serving yet (attempt 1) — waiting for it, then re-syncing` and heals itself.
With `install.sh`, phase boundaries are the `── phase: NN ──` markers;
capture stdout to a file and read it with `tr '\r' '\n'` (k3s and helmfile
emit `\r` progress). 02 prints a **BACK UP the age key** warning — relay it
to the user verbatim in your final report. Without Vault, run 07 without
`--verify` (the verification is the Vault pipeline proof).

**The one-time admin password — do exactly this.** 07 prints it once ("shown
ONCE — store it now"), so if you captured stdout your capture file now holds
the only copy in plaintext. That is expected; do not pretend otherwise and do
not try to scrub it after the fact. Instead, hand it over deterministically:

1. `chmod 600 <capture file>` as soon as the run finishes.
2. In your report, give the **path** and the label to look for
   (`tenant admin login`) — never the value itself.
3. Tell the user to store it in their password manager and then destroy the
   capture: `shred -u <capture file>`.

Never copy the value into your report, into another file, or into a
`kubectl`/`curl` command you echo. If you need it yourself (e.g. for
`08-token.sh`), read it from the capture in the same command that uses it, so
it is never printed.

## 4. On failure

Do not retry blindly and do not improvise cluster surgery:

1. Read the actual error from the script output (and `kubectl get pods
   -n egov`, pod logs) — then look it up in the **gotchas table** at the end
   of `deploy-as-code/helm/charts/digit3/INSTALL.md`. Nearly every known
   failure mode is mapped to its fix there. Most common transient: the SSH
   tunnel dropped. From inside a phase it looks like `06` ending with
   `rollout status … timed out waiting for the condition` (or any script
   dying on a kubectl call); run `kubectl get pods -n egov` yourself and you
   get `connection refused 127.0.0.1:<tunnel port 01-cluster printed>` or
   `TLS handshake timeout` — while the pods are in fact Ready. Fix: re-run
   `./01-cluster.sh <key> <domain>` (idempotent — reopens the tunnel,
   rewrites the kubeconfig), then re-run the interrupted script.
2. Apply the mapped fix, then **re-run the same script** — idempotence makes
   this safe.
3. If the symptom is not in the table, stop and report to the user with the
   error, the phase, and your best diagnosis.

Standing rules: never print secret values (the scripts keep credentials off
screen, except 07's one-time admin password — see §3; keep it that way in any
ad-hoc debugging); always helmfile `sync`,
never `apply`; exactly one deployment shape at a time (the shapes publish the
same ingress paths and kong prefixes).

## 5. Wrap-up report

End with:

- the 07-seed PASS/FAIL verification table (API plaintext / `vault:v1:…` +
  HMAC in the DB / per-tenant transit key), or the seed summary without Vault
- the tenant code 07-seed printed (`tenant code: …`), and for the one-time
  admin password: the capture file's **path**, the `tenant admin login` label
  to look for, and the `shred -u <path>` line — never the value (§3)
- `export KUBECONFIG=<path 01-cluster printed>` for manual kubectl use — the
  authoritative value is `KUBECONFIG_PATH` in `scripts/.env` (default
  `~/modulith-kubeconfig.yaml`; the tunnel port is `TUNNEL_PORT` in `lib.sh`,
  default 16443)
- the age-key backup warning
- ongoing ops: Vault pod restart → re-run `04-vault.sh` (it just unseals);
  VM reboot / kubectl timeouts → re-run `01-cluster.sh`; new images → re-run
  `06-deploy.sh <digit3> <shape> <new-tag>`; new tenant → `07-seed.sh`;
  API token for a tenant user → `08-token.sh <TENANT-CODE> <email>` (the
  password 07 printed; prompted if omitted)
