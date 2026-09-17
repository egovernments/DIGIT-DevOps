# DIGIT 3 — One-Step Install

`scripts/install.sh` orchestrates the whole install — phases 01–07 in order —
from a single command. It is a thin wrapper over the numbered phase scripts
(which remain independently runnable); it gathers inputs once, prompts for
anything missing, and stops on the first failure with the exact command to
resume from. Every phase is idempotent, so re-running is always safe.

Prerequisites are the same as the step-by-step runbook
([INSTALLATION-STEPS.md](INSTALLATION-STEPS.md) steps 1–3): the workstation
toolchain, both repos cloned, and a reachable VM with DNS.

## Interactive (prompts for anything you omit)

```bash
cd deploy-as-code/helm/charts/digit3/scripts
./install.sh --key <ssh-key> --domain <domain>
```

It will prompt for the **deployment shape** (single-container / domain-bundles
/ per-service), the digit3 repo path, and the tenant name + admin email, then
run straight through to a verified platform.

## Fully specified (non-interactive)

```bash
./install.sh \
  --key    ~/Documents/modulith/domain-split-key \
  --domain domain-split.digit.org \
  --shape  single-container \
  --digit3 ~/Documents/modulith/digit3 \
  --tenant "Demo Tenant" \
  --email  admin@example.org
```

| Flag | Meaning | Prompted if omitted? |
|---|---|---|
| `--key` | SSH private key for the VM | yes |
| `--domain` | VM hostname (no `user@`) | yes |
| `--shape` | `single-container` \| `domain-bundles` \| `per-service` | yes (menu) |
| `--digit3` | path to the digit3 checkout | yes |
| `--tenant` | tenant name to seed (code derives UPPERCASE) | yes |
| `--email` | tenant admin email | yes |
| `--vm-user` | SSH user | no (default `azureuser`) |

Non-interactive runs (no TTY, e.g. CI) must pass every required flag — a
missing one errors instead of hanging on a prompt.

## What it runs

```
01-cluster   k3s install + SSH tunnel + kubeconfig
02-secrets   age key, sops rule, encrypted secrets (fresh passwords), domain
03-backbone  backbone sync + keycloak DB/role (+ webhook & consumer self-heal)
04-vault     init/unseal, transit + approle, credentials into sops
05-images    Docker-Hub-first: verify published pins (build only if missing)
06-deploy    chart gen + service-host map + shape helmfile sync + kong
07-seed      tenant + idgen template + Vault encryption verification
```

On success it prints the tenant admin's one-time password, the KUBECONFIG
line, and how to mint an API token (`08-token.sh`). On failure it names the
phase and the resume command; fix per the gotchas table in
[INSTALL.md](INSTALL.md) and re-run — either `./install.sh …` again (earlier
phases no-op) or just the single failed phase script.

## When to use which

- **`install.sh`** — you want it done in one command, hands-off.
- **[INSTALLATION-STEPS.md](INSTALLATION-STEPS.md)** — you want to run each
  phase yourself and inspect between steps.
- **the `/install-digit` skill** — you want Claude Code to drive it, asking
  you the shape and inputs conversationally.

All three call the same scripts and produce the same result.
