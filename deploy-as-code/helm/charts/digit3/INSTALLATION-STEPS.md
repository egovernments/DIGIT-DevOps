# DIGIT 3 on k3s — Installation Steps

DIGIT 3 with Vault PII encryption in **9 steps**, in your choice of three
**out-of-the-box shapes** — pre-generated charts, pinned published images:

| Shape (`--shape`) | Containers | What it is |
|---|---|---|
| `single-container` (default) | 1 | all 16 services in one JVM (`dev-bundle`) |
| `domain-bundles` | 4 | identity / notification / billing / admin bundles |
| `per-service` | 16 | every service its own pod |

> **Just want one command?** See [ONE-STEP-INSTALL.md](ONE-STEP-INSTALL.md) —
> `scripts/install.sh` runs steps 4–9 for you. This page is the phase-by-phase
> path for running (and inspecting between) each script yourself.

Steps 4–9 are the numbered scripts in [`scripts/`](scripts/) — each is
idempotent (safe to re-run; a completed phase converges to a no-op) and
prints the next command when it finishes. Deploy exactly ONE shape at a time
(they publish the same ingress paths). Background, shape internals, and the
troubleshooting table live in [INSTALL.md](INSTALL.md). The pre-rename shape
names `dev-bundle` / `domain-split` / `services` are still accepted as
synonyms.

Placeholders: `<key>` = SSH private key, `<domain>` = the VM's DNS name,
`<tag>` = a published image tag (`modulith-<sha>` from the Actions builds).

## Steps

**1. Install the workstation toolchain** — `kubectl`, `helm` (v4),
`helmfile` (v1.7+), `sops`, `age`, `jq`, and `python3` with `pyyaml` +
`requests`. `docker` + JDK 25 + Maven only if you build images yourself
(step 8's optional `05-build.sh`).

**2. Clone both repos side by side (both on `modulith`):**

```bash
cd ~/Documents
git clone -b modulith https://github.com/egovernments/DIGIT-DevOps.git
git clone -b modulith https://github.com/digitnxt/digit3.git
```

**3. Provision the VM** — Ubuntu 22.04 (8 vCPU, 16–32 GB RAM, 100 GB disk),
map its public IP to `<domain>`, open port 22 (defer 80/443 until you need
Let's Encrypt).

**4. Cluster** — installs k3s (Traefik disabled), opens the API tunnel on
`127.0.0.1:16443`, writes a tunnel-ready kubeconfig, and saves the
connection settings to `scripts/.env` for the later scripts:

```bash
cd ~/Documents/DIGIT-DevOps/deploy-as-code/helm/charts/digit3/scripts
./01-cluster.sh <key> <domain>
```

**5. Secrets** — creates (or reuses) the age key, registers the recipient in
`.sops.yaml` (covering the per-environment `azure-k3s-secrets.<domain>.yaml`
files too), and generates the encrypted secrets with fresh credentials.
**Back up the age key it points at — it is the only key to the secrets:**

```bash
./02-secrets.sh
```

**6. Backbone** — deploys cluster-configs, cert-manager (self-healing the
webhook race), ingress-nginx, postgres, redis, minio (provisioning
filestore's bucket) and Kafka, then creates the Keycloak database **and** role
from the `kc-db` secret:

```bash
./03-backbone.sh
```

**7. Vault** — deploys Vault, initializes it (keys go straight into the sops
file, never onto disk), unseals, enables transit + AppRole (reconciling stored
credentials against the live role), and re-renders the `vault-approle` k8s
secret. Skip if you don't want PII encryption (then set `VAULT_ENABLED: "false"`
in the shape's env blocks first):

```bash
./04-vault.sh
```

**8. Deploy** — `06` regenerates the shape's bundle charts, ensures the
database, syncs the shape's helmfile with the image tag supplied as
`DIGIT_TAG`, and programs Kong (waiting for its Admin API). The shape's domain
and `egov-service-host` keys come from `environments/azure-k3s-<shape>.yaml`,
layered by the helmfile — no env file is mutated. Positional args:
`<digit3-path> <shape> <tag>`:

```bash
./06-deploy.sh ~/Documents/digit3 single-container <tag>   # or domain-bundles | per-service
```

**`05-build.sh` is optional** — the OOB shapes use published images, so you
normally skip it. Run it only to build images from your own digit3 tree; it
side-loads them into the node's containerd and records the tag for `06`:

```bash
./05-build.sh ~/Documents/digit3                 # optional; local image build
```

**9. Seed + verify** — creates a tenant (Keycloak realm + per-tenant schema
via the tenant-migration event), waits for the full fan-out, seeds the runtime
lookups (otp configs, idgen templates, the OTP SMS template), prints the tenant
admin password ONCE, and with `--verify` proves the Vault pipeline end to end
(API plaintext, DB `vault:v1:…` ciphertext + HMAC blind index, per-tenant
transit key):

```bash
./07-seed.sh "My Tenant" admin@example.org --verify
```

Mint an API token for a tenant user afterward:
`./08-token.sh <TENANT-CODE> <email> [password]` — the password step 9
printed; omitted, it is prompted for (so pass it when scripting).

## Ongoing operations

- **After any Vault pod restart** the Shamir seal closes — re-run
  `./04-vault.sh` (it detects the initialized state and just unseals from
  the sops file).
- **After a VM reboot** (or when kubectl starts timing out) — re-run
  `./01-cluster.sh <key> <domain>` to re-open the tunnel.
- **New image tag** — re-run `./06-deploy.sh <digit3> <shape> <new-tag>`.
- **Switching shapes** — uninstall the old shape's releases first
  (`helm uninstall <release> -n egov` for each), then
  `./06-deploy.sh <digit3> <new-shape> <tag>`. Every shape uses the same
  default `postgres` database (tenants separate by schema), so the data is
  simply still there after a switch — nothing is migrated or copied.
- **New tenant** — `./07-seed.sh "Name" email@org` (the idgen `individual`
  template is part of seeding; individuals fail with `idgen 404 template
  not found` without it).
- Anything failing? Start with the **gotchas table** at the end of
  [INSTALL.md](INSTALL.md) — it maps symptoms to fixes.
- Want a grouping other than the three stock shapes? See
  [CUSTOM-BUNDLING.md](CUSTOM-BUNDLING.md) — phases 01–04 are identical; only
  the build + deploy half changes.
