# DIGIT 3 — One-Step Install

Install DIGIT 3 (with Vault PII encryption) on a single-node k3s VM with a
single command. `scripts/install.sh` orchestrates all phases — cluster,
secrets, backbone, Vault, deploy, seed+verify — prompting for anything you
don't pass as a flag. It is a thin wrapper over the numbered phase scripts
(which stay independently runnable), and every phase is idempotent, so
re-running after any hiccup is always safe.

This page is self-contained: follow it top to bottom.

---

## 1. Workstation prerequisites

You need these on the machine you run the install *from* (not the VM):

`kubectl`, `helm` (v4), `helmfile` (v1.7+), `sops`, `age`, `jq`, `docker`
(with buildx, only for the optional local image build), and `python3` with
`pyyaml` + `requests`. JDK 25 (Temurin) and Maven 3.9+ are needed **only** if
you build images from source (`05-build.sh`); the out-of-the-box shapes use
published images and need neither.

**macOS (Homebrew):**

```bash
brew install kubernetes-cli helm helmfile sops age jq
brew install --cask docker      # start Docker Desktop once, so the daemon runs
pip3 install pyyaml requests
```

**Debian/Ubuntu:** install `kubectl`, `helm`, `helmfile`, `sops`, `age`, `jq`,
`docker.io` (+ buildx), and `python3-yaml` / `python3-requests` from your
package manager or each project's release page.

Verify:

```bash
for t in kubectl helm helmfile sops age jq docker python3; do command -v $t || echo "MISSING $t"; done
python3 -c "import yaml, requests; print('python deps ok')"
```

(The install script preflights these too and stops early if any is missing.)

---

## 2. Clone both repos

`DIGIT-DevOps` holds the charts, environments, and scripts; `digit3` holds the
service source, the bundle manifests, and Kong's bootstrap. Both on `modulith`:

```bash
cd ~/Documents        # or wherever you keep repos
git clone -b modulith https://github.com/egovernments/DIGIT-DevOps.git
git clone -b modulith https://github.com/digitnxt/digit3.git
```

---

## 3. Provision the VM (one-time, outside the script)

- Ubuntu 22.04 VM: ≥ 8 vCPU / 16 GB RAM (32 GB comfortable), 100 GB disk.
- Map its public IP to your domain (e.g. `my-digit.example.org`).
- Open port **22** now (80/443 only when you later want public TLS).
- You need an SSH **private key** that logs into the VM as `azureuser`
  (or pass a different user with `--vm-user`).

That's the only manual infrastructure step — everything else is the script.

---

## 4. Run it

```bash
cd DIGIT-DevOps/deploy-as-code/helm/charts/digit3/scripts
```

**Interactive** — prompts for shape, digit3 path, tag, and tenant details:

```bash
./install.sh --key ~/path/to/ssh-key --domain my-digit.example.org
```

**Fully specified** — non-interactive (required for CI: a missing flag errors
rather than hanging on a prompt):

```bash
./install.sh \
  --key    ~/path/to/ssh-key \
  --domain my-digit.example.org \
  --shape  single-container \
  --tag    modulith-39f619d \
  --digit3 ~/Documents/digit3 \
  --tenant "Demo Tenant" \
  --email  admin@example.org
```

| Flag | Meaning | Prompted if omitted? |
|---|---|---|
| `--key` | SSH private key for the VM | yes |
| `--domain` | VM hostname (no `user@`) | yes |
| `--shape` | `single-container` \| `domain-bundles` \| `per-service` | yes (3-way menu) |
| `--tag` | published image tag (`modulith-<sha>`) — preflighted against Docker Hub | yes |
| `--digit3` | path to the digit3 checkout | yes |
| `--tenant` | tenant name to seed (code derives UPPERCASE) | yes |
| `--email` | tenant admin email | yes |
| `--vm-user` | SSH user | no (default `azureuser`) |
| `--skip-vault` | skip Vault (PII stored plaintext; set `VAULT_ENABLED: "false"` in the shape's env blocks first) | no |

The pre-rename names `dev-bundle` / `domain-split` / `services` are still
accepted as synonyms for `single-container` / `domain-bundles` / `per-service`.

### The three shapes

| Shape | Containers | Notes |
|---|---|---|
| `single-container` | 1 | all 16 services in one JVM (~0.5 GB) — smallest, recommended |
| `domain-bundles` | 4 | identity / notification / billing / admin — scale per group |
| `per-service` | 16 | every service its own pod (~5 GB) — classic microservices |

Deploy exactly one shape at a time (they publish the same ingress paths).

---

## 5. What it runs

```
preflight    verify every image the shape needs exists on Docker Hub at --tag
01-cluster   k3s install + SSH tunnel + kubeconfig
02-secrets   age key, sops rule, encrypted secrets (fresh random passwords)
03-backbone  backbone sync (self-heals the cert-manager webhook race) + keycloak DB/role + minio bucket
04-vault     init/unseal, transit + approle, credentials into sops (skipped with --skip-vault)
06-deploy    chart gen + shape helmfile sync with DIGIT_TAG + kong (waits for kong's Admin API)
07-seed      tenant (with admin password) + runtime seeds + Vault encryption verification
```

`05-build.sh` is **not** run by `install.sh` — it is the optional path for
building images from your own digit3 tree; the stock shapes pull the published
`--tag` images. Each shape's domain and `egov-service-host` keys come from its
overlay (`environments/azure-k3s-<shape>.yaml`), layered by its helmfile; image
tags come solely from `DIGIT_TAG`. No tracked file is mutated at deploy time.

On success it prints:
- the **tenant admin's one-time password** — store it (SMTP is a placeholder,
  so this is the only delivery)
- `export KUBECONFIG=~/modulith-kubeconfig.yaml` for kubectl
- how to mint an API token: `./08-token.sh <TENANT-CODE> <email>`

**Back up `~/.config/sops/age/keys.txt`** off this machine — it is the only
key to the secrets (and to Vault's unseal key).

---

## 6. If a phase fails

The script stops at the failing phase and prints the exact resume command.
Fix per the **gotchas table** at the end of [INSTALL.md](INSTALL.md), then
either re-run `./install.sh …` (earlier phases no-op) or just the one failed
phase script. Common transient: kubectl `TLS handshake timeout` /
`connection refused 127.0.0.1:16443` mid-run means the SSH tunnel dropped —
re-run `./01-cluster.sh <key> <domain>` and continue.

## 7. Other ways in (same scripts, same result)

- **[INSTALLATION-STEPS.md](INSTALLATION-STEPS.md)** — run each phase yourself
  and inspect between steps.
- **the `/install-digit` skill** — have Claude Code drive it, asking you the
  shape and inputs conversationally.
