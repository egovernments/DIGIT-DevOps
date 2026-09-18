# DIGIT 3 on k3s — scripted installation

Any of the three deployment shapes — **services** (16 pods),
**dev-bundle** (one modulith JVM) or **domain-split** (4 bundle JVMs) — with
optional **Vault PII encryption**, in 8 steps. Steps 4–8 are the numbered
scripts in [`scripts/`](scripts/) — each is idempotent (safe to re-run; a
completed phase converges to a no-op) and prints the next command when it
finishes. Background, shape details and the troubleshooting table live in
[INSTALL.md](INSTALL.md).

Placeholders: `<key>` = SSH private key, `<domain>` = the VM's DNS name,
`<shape>` = `services|dev-bundle|domain-split`, `<tag>` = the image tag
(`modulith-<sha>` from the GitHub Actions builds).

## One command

Everything below, in one go (prompts for anything omitted; on failure it
stops with the exact resume command, and re-running no-ops through
completed phases):

```bash
cd deploy-as-code/helm/charts/digit3/scripts
./install.sh --key <key> --domain <domain> --digit3 <digit3-path> \
  --shape services|dev-bundle|domain-split --tag modulith-<sha> \
  --tenant "My Tenant" --email admin@example.org
```

It preflights every image the shape needs against Docker Hub, runs phases
01→04, deploys with `DIGIT_TAG=<tag>`, seeds a tenant (printing the admin
password ONCE) and, with Vault, verifies the PII pipeline. `--skip-vault`
skips phase 04 (set `VAULT_ENABLED: "false"` in the shape's env blocks
first). The step-by-step path below remains for understanding and for
resuming individual phases.

## Steps

**1. Workstation toolchain** — `kubectl`, `helm` (v4), `helmfile` (v1.7+),
`sops` + `age`, `docker` (only for locally-built bundle images), `python3`
with `pyyaml` and `requests`.

**2. Clone both repos on the `modulith` branch:**

```bash
git clone -b modulith <DIGIT-DevOps remote>
git clone -b modulith <digit3 remote>
```

**3. Provision the VM** — Ubuntu 22.04 (8 vCPU, 16–32 GB RAM, 100 GB disk),
map its public IP to `<domain>`, open port 22 (defer 80/443 until you need
Let's Encrypt).

**4. Cluster** — installs k3s (Traefik disabled), opens the API tunnel,
writes a tunnel-ready kubeconfig, and saves the connection settings to
`scripts/.env` for the later scripts:

```bash
cd deploy-as-code/helm/charts/digit3
./scripts/01-cluster.sh <key> <domain>
```

**5. Secrets** — age key (reused if present), sops creation rule, and a
fresh-credential secrets file:

```bash
./scripts/02-secrets.sh
```

**6. Backbone** — cluster-configs, cert-manager, ingress, postgres, redis,
minio, kafka, plus the keycloak database and role:

```bash
./scripts/03-backbone.sh
```

**7. Vault (optional)** — deploys Vault, initializes it (keys go straight
into the sops file, never onto disk), unseals, enables transit + AppRole
(`digit-services`, full `digit-transit` policy), and renders the
`vault-approle` k8s secret. Skip if you don't want PII encryption (then set
`VAULT_ENABLED: "false"` in the shape's env blocks before deploying):

```bash
./scripts/04-vault.sh
```

**8. Deploy + seed** — picks the shape's helmfile (which layers its
`environments/azure-k3s-<shape>.yaml` overlay), tags every digit3 image from
the single `DIGIT_TAG` input, programs Kong from the same manifest, then
seeds a tenant plus the runtime lookups (otp configs, idgen templates, the
OTP SMS template). `--verify` proves the Vault pipeline end to end (API
plaintext, DB `vault:v1:…` ciphertext + HMAC blind index, per-tenant transit
key):

```bash
./scripts/06-deploy.sh <path-to-digit3> <shape> <tag>
./scripts/07-seed.sh "My Tenant" admin@example.org --verify
```

(`05-build.sh <path-to-digit3> [manifest]` is the optional offline path: it
builds the bundle images locally from the checkout and side-loads them into
containerd; `06-deploy.sh` then defaults its tag from
`scripts/.last-build-tag`. The services shape always uses Actions images.)

## Ongoing operations

- **After any Vault pod restart** the Shamir seal closes — re-run
  `./scripts/04-vault.sh` (it detects the initialized state and just unseals
  from the sops file).
- **After a VM reboot** (or when kubectl starts timing out) — re-run
  `./scripts/01-cluster.sh <key> <domain>` to re-open the tunnel.
- **Switching shape** — re-run `06-deploy.sh` with the other shape after
  removing the previous shape's releases (the shapes publish the same ingress
  paths and kong prefixes; see INSTALL.md §4).
