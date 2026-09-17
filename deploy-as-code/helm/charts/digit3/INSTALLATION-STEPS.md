# DIGIT 3 on k3s — Installation Steps

DIGIT 3 with Vault PII encryption in **9 steps**, in your choice of three
**out-of-the-box shapes** — pre-generated charts, pinned published images,
no chart generation or image building required:

| Shape (`--shape`) | Containers | What it is |
|---|---|---|
| `single-container` (default) | 1 | all 16 services in one JVM (`dev-bundle`) |
| `domain-bundles` | 4 | identity / notification / billing / admin bundles |
| `per-service` | 16 | every service its own pod |

Steps 4–9 are the numbered scripts in [`scripts/`](scripts/) — each is
idempotent (safe to re-run; a completed phase converges to a no-op) and
prints the next command when it finishes. Deploy exactly ONE shape at a time
(they publish the same ingress paths). Background, shape internals, and the
troubleshooting table live in [INSTALL.md](INSTALL.md); the fully manual
command-by-command path is in the history of this file
(`git log -- INSTALLATION-STEPS.md`).

Placeholders: `<key>` = SSH private key, `<domain>` = the VM's DNS name.

## Steps

**1. Install the workstation toolchain** — `kubectl`, `helm` (v4),
`helmfile` (v1.7+), `sops`, `age`, `jq`, `docker` with buildx, JDK 25
(Temurin), Maven 3.9+, and `python3` with `pyyaml` + `requests`.

**2. Clone both repos side by side:**

```bash
cd ~/Documents
git clone -b modulith-vault https://github.com/egovernments/DIGIT-DevOps.git
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
`.sops.yaml`, generates the encrypted secrets file with fresh credentials,
and stamps your domain into the environment file. **Back up the age key it
points at — it is the only key to the secrets:**

```bash
./02-secrets.sh
```

**6. Backbone** — deploys cluster-configs, cert-manager, ingress-nginx,
postgres, redis, minio and Kafka, then creates the Keycloak database **and**
role from the `kc-db` secret:

```bash
./03-backbone.sh
```

**7. Vault** — deploys Vault, initializes it (keys go straight into the sops
file, never onto disk), unseals, enables transit + AppRole, and re-renders
the `vault-approle` k8s secret. Skip this step if you don't want PII
encryption:

```bash
./04-vault.sh
```

**8. Images + deploy** — `05` is Docker-Hub-first: the published egovio
images pinned in the environment file are verified and **nothing is built**
(pass a custom TAG to build your own digit3 tree instead — bundle shapes
only). `06` regenerates the shape's charts, derives the `egov-service-host`
keys from the manifest (re-syncing cluster-configs), ensures the database,
pins tags only when a local build happened, deploys the shape's helmfile, and
programs Kong:

```bash
./05-build.sh ~/Documents/digit3                 # add --shape domain-bundles | per-service
./06-deploy.sh ~/Documents/digit3                # same --shape; persisted for later scripts
```

Run interactively without `--shape` (and no shape persisted from a previous
run), `06-deploy.sh` presents the three-shape menu; under automation it
defaults to `single-container`. The `--shape` flag is accepted anywhere on
the command line, and unknown options are rejected loudly.

**9. Seed + verify** — creates a tenant (Keycloak realm + per-tenant schema
via the tenant-migration event), registers its `individual` idgen template,
and with `--verify` proves the Vault pipeline end to end (API plaintext, DB
`vault:v1:…` ciphertext + HMAC blind index, per-tenant transit key):

```bash
./07-seed.sh "My Tenant" admin@example.org --verify
```

## Ongoing operations

- **After any Vault pod restart** the Shamir seal closes — re-run
  `./04-vault.sh` (it detects the initialized state and just unseals from
  the sops file).
- **After a VM reboot** (or when kubectl starts timing out) — re-run
  `./01-cluster.sh <key> <domain>` to re-open the tunnel.
- **New app build** — re-run `./05-build.sh` + `./06-deploy.sh` (the new
  git-derived tag is pinned and rolled out automatically).
- **Switching shapes** — uninstall the old shape's releases first
  (`helm uninstall <release> -n egov` for each), then run
  `./06-deploy.sh --shape <new-shape> …`; bundle shapes share `bundle_db`,
  per-service uses `postgres` — independent datasets, switching does not
  migrate data.
- **New tenant** — `./07-seed.sh "Name" email@org` (the idgen `individual`
  template is part of seeding; individuals fail with `idgen 404 template
  not found` without it).
- Anything failing? Start with the **gotchas table** at the end of
  [INSTALL.md](INSTALL.md) — it maps symptoms to fixes.
