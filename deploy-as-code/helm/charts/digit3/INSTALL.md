# DIGIT 3 on single-node k3s — installation guide

> Just installing the single-modulith shape? Follow the 30-step runbook in
> [INSTALLATION-STEPS.md](INSTALLATION-STEPS.md) — every command and file
> edit in order. This guide is the reference behind it.

DIGIT 3 has no fixed deployment shape: **which services share a JVM is
declared in one manifest per shape** (`src/bundles/<shape>.package.yaml` in
the digit3 repo — `dev-bundle.package.yaml`, `domain-split.package.yaml`),
and every layer — the bundle jars, their Docker images, the helm
charts, and kong's routing — is derived from it. Any grouping of the 16 core
services is a valid deployment. Out of the box, three configurations are
provided:

| # | Configuration | Containers (core services) | Manifest | Bundler needed? |
|---|---|---|---|---|
| 1 | **Per-service** — every service its own pod | 16 | none | **No** |
| 2 | **Single modulith** — everything in one JVM (`dev-bundle`) | 1 | [`dev-bundle.package.yaml`](https://github.com/digitnxt/digit3/blob/modulith/src/bundles/dev-bundle.package.yaml) (`modulith` branch) | Yes |
| 3 | **Domain bundles** — four JVMs along building-block lines | 4 | [`domain-split.package.yaml`](https://github.com/digitnxt/digit3/blob/modulith/src/bundles/domain-split.package.yaml) (`modulith` branch) | Yes |

Configuration 3's grouping:

| Bundle | Services |
|---|---|
| `identity-bundle` | otp, individual, employee, account |
| `notification-bundle` | template-config, notification, url-shortener |
| `billing-bundle` | billing, apportion, pg-service |
| `admin-bundle` | idgen, localization, workflow, registry, filestore, boundary |

All three run on the **same foundation** (Section 1): k3s, secrets, backbone
infra, keycloak, kong. External behavior is identical in every shape — each
service keeps its standalone URL (`/billing/v3/…`), kong keeps the same
routes/plugins, and only the upstreams differ. Deploy exactly one shape at a
time (they publish the same ingress paths). Measured trade-off: 16 JVMs ≈
5 GB vs the single modulith ≈ 0.5 GB; grouped bundles sit in between and buy
independent scaling/releases per group.

Reference deployment: `modulith.digit.org` (Azure VM, 8 vCPU / 32 GB / 100 GB,
Ubuntu 22.04). Repos: `DIGIT-DevOps` (this repo — charts, environments,
chart bundler) and `digit3` (service source, bundle generator, kong
bootstrap), branches per the table above.

Workstation prerequisites: `kubectl`, `helm` (v4 tested), `helmfile` (v1.7+),
`sops` + `age`, `docker` (buildx), JDK 25 (Temurin), Maven 3.9+, `python3`
with `pyyaml` and `requests`.

---

## 1. Common foundation (required for EVERY configuration)

### 1.1 Provision the VM and DNS

- Ubuntu 22.04 VM, ≥8 vCPU / 16 GB (32 GB comfortable), 100 GB disk.
- Map its public IP to your domain (here `modulith.digit.org`).
- NSG/firewall: open **22** now; open **80/443** when you want Let's Encrypt
  certificates and public access (everything below works without them via
  SSH + in-cluster curl).

### 1.2 Install k3s (Traefik disabled — we run ingress-nginx)

```bash
ssh -i <key> azureuser@<domain>
curl -sfL https://get.k3s.io | sh -s - --disable traefik
sudo k3s kubectl get nodes    # wait for Ready
```

k3s ships `local-path` as the default StorageClass and klipper ServiceLB,
which later gives the ingress-nginx LoadBalancer the node's IP on 80/443.

### 1.3 kubeconfig over an SSH tunnel

If 6443 is not open in the NSG (recommended), tunnel it:

```bash
# on the workstation — re-run after VM reboots or if kubectl starts timing out
ssh -f -N -L 16443:127.0.0.1:6443 -i <key> azureuser@<domain>
# "Address already in use" → a tunnel exists; test kubectl, and if stale:
#   pkill -f "16443:127.0.0.1:6443"   then re-run the ssh command

ssh -i <key> azureuser@<domain> 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/modulith-kubeconfig.yaml

# point the kubeconfig at the tunnel port — the file ships with 6443, and
# kubectl fails with "connection refused 127.0.0.1:6443" if you skip this
sed -i '' 's|server: https://127.0.0.1:6443|server: https://127.0.0.1:16443|' ~/modulith-kubeconfig.yaml   # macOS
# sed -i 's|server: https://127.0.0.1:6443|server: https://127.0.0.1:16443|' ~/modulith-kubeconfig.yaml    # Linux

# optional but recommended: rename context/cluster/user from `default` to `modulith`
export KUBECONFIG=~/modulith-kubeconfig.yaml
kubectl get nodes
```

Keep this kubeconfig in its **own file** (not merged into `~/.kube/config`)
so mutating commands can never accidentally target another cluster.

> `kubectl port-forward` through this tunnel is unreliable for data transfer.
> For in-cluster calls, prefer `ssh <vm> 'curl http://<ClusterIP>:…'`.

### 1.4 Secrets: fresh credentials, encrypted with age

No AWS/KMS dependency. One-time:

```bash
age-keygen -o ~/.config/sops/age/keys.txt        # BACK THIS FILE UP — only key to the secrets
# "file exists" → you already have a key; REUSE it (a new one can't decrypt old
# secrets). Print its recipient for .sops.yaml with:
#   age-keygen -y ~/.config/sops/age/keys.txt
# macOS sops looks elsewhere:
mkdir -p ~/Library/Application\ Support/sops/age
ln -sf ~/.config/sops/age/keys.txt ~/Library/Application\ Support/sops/age/keys.txt
```

Add a creation rule to `deploy-as-code/helm/.sops.yaml` with your age
recipient for `environments/azure-k3s-secrets.yaml`, then create the secrets
file (same YAML shape as `test-lts-secrets.yaml`: `cluster-configs.secrets.*`
for db, minio, kc-db, kc-admin, hmac, citizen-broker, employee-iam,
kafka-kraft `kraft-cluster-id`, plus SMTP/SMS/Stripe placeholders) with fresh
generated passwords, and encrypt in place:

```bash
sops -e -i environments/azure-k3s-secrets.yaml
```

`helm-secrets` does not work with helm v4, so `charts/digit3/deploy.sh`
decrypts to `environments/azure-k3s-secrets.dec.yaml` (git-ignored — ensure
`*.dec.yaml` is in `.gitignore`), runs helmfile, and deletes the file on exit.

### 1.5 The environment file

`environments/azure-k3s.yaml` is the single overlay for everything:

- `global.domain: <your domain>`
- `cluster-configs:` — namespaces `[backbone, cert-manager, egov, health,
  keycloak, monitoring, playground]`, `egov-config` data (`db-host` must be
  **host only** — kong reads it as `KONG_PG_HOST`; `db-url` the full JDBC
  URL; `kafka-brokers: release-name-kafka-controller-headless.backbone:9092`),
  `egov-service-host` map, root-ingress → `kong-kong-proxy:8000`.
- One block per release pinning **image tags** (mandatory — chart defaults
  resolve to `:latest` which do not exist).

### 1.6 Deploy the backbone

```bash
cd deploy-as-code/helm/charts/digit3
export KUBECONFIG=~/modulith-kubeconfig.yaml
./deploy.sh -f backboneservices-helmfile.yaml sync
```

Always `sync`, never `apply` (helm-diff is broken on helm v4). Order enforced
via `needs:`: **cluster-configs first** (namespaces, ConfigMaps, all
secrets), then cert-manager → ingress-nginx, postgres (release name
`postgresql-lts` — it *is* the DB hostname), redis, minio (single replica),
and Kafka whose release name **must be `release-name`** so the
`kafka-brokers` DNS resolves. If cert-manager's ClusterIssuer fails with "no
endpoints available", re-run sync once the webhook pod is ready.

### 1.7 Keycloak database

```bash
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -c "CREATE DATABASE new_keycloak"

# create the `keycloak` role with the credentials from the kc-db secret
# (rendered by cluster-configs, so role and pod can never disagree; the
# password stays off-screen). Skipping this crash-loops Keycloak with
# 'password authentication failed for user "keycloak"'.
U=$(kubectl get secret kc-db -n keycloak -o jsonpath='{.data.username}' | base64 -d)
P=$(kubectl get secret kc-db -n keycloak -o jsonpath='{.data.password}' | base64 -d)
printf "CREATE ROLE %s LOGIN PASSWORD '%s';
GRANT ALL PRIVILEGES ON DATABASE new_keycloak TO %s;
ALTER DATABASE new_keycloak OWNER TO %s;\n" "$U" "$P" "$U" "$U" | \
  kubectl exec -i -n egov postgresql-lts-0 -- psql -U postgres
```

(Keycloak itself is installed by the services helmfile in every shape.)

### 1.8 Optional: HashiCorp Vault (PII encryption at rest)

Services with PII (individual, otp) can encrypt fields via Vault's **Transit**
engine — stored as `vault:v1:…` ciphertext with a keyed HMAC blind index for
search, one transit key **per tenant** (auto-created on first encrypt).
Everything runs with `VAULT_ENABLED=false` until you do this.

**Deploy** (chart: `charts/digit3/vault`, official HashiCorp 0.29.1 adapted
from the test-lts copy — de-AWS'd: no `gp2` storageClass, no `awskms`
auto-unseal, no hardcoded auth-config sidecar, no public `/ui`+`/v1` ingress,
namespace `vault` not `vault-new`):

```bash
# env: `vault` in the cluster-configs namespace list; egov-config vault-host +
# egov-service-host vault keys point at ...vault.svc.cluster.local:8200
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync
./deploy.sh -f backboneservices-helmfile.yaml -l name=vault sync
```

**Init + unseal** (Shamir seal — repeat the unseal after EVERY pod restart):

```bash
# 1. initialize — writes the unseal key + root token to init.json (PLAINTEXT — handle with care)
kubectl exec vault-0 -n vault -- vault operator init -key-shares=1 -key-threshold=1 -format=json \
  > init.json

# 2. unseal — the in-pod command reads the key on stdin, so pipe it in
#    (run bare, it sits waiting for input and looks stuck)
jq -r '.unseal_keys_b64[0]' init.json | \
  kubectl exec -i vault-0 -n vault -- sh -c 'read -r K; vault operator unseal "$K"'

# 3. store unseal_keys_b64[0] + root_token in the sops file under `vault-operator:`
#    (unseal-key / root-token), THEN delete the plaintext. Skipping this leaves
#    secrets in the repo and breaks the re-unseal command below after any re-init.
sops environments/azure-k3s-secrets.yaml
rm init.json
```

After any pod restart, Vault is sealed again (individual's PII encrypt/decrypt
calls fail until unsealed — the service itself stays up). Re-unseal straight
from the sops file, key never displayed:

```bash
sops -d --extract '["vault-operator"]["unseal-key"]' environments/azure-k3s-secrets.yaml | \
  kubectl exec -i vault-0 -n vault -- sh -c 'read -r K; vault operator unseal "$K"'
```

Note the two credentials are different things: the **unseal key** decrypts
Vault's keyring at startup; the **root token** merely authenticates admin API
calls and cannot unseal. For real auto-unseal on Azure, configure a
`seal "azurekeyvault"` stanza (the Azure analogue of test-lts's awskms) —
requires an Azure identity.

**Enable transit + AppRole** (as root, inside the pod):

```bash
# 1. print the root token from the sops file (clear the terminal after use)
sops -d --extract '["vault-operator"]["root-token"]' environments/azure-k3s-secrets.yaml

# 2. shell into the pod and authenticate — paste the token at the login prompt
kubectl exec -it vault-0 -n vault -- sh
vault login
```

Inside the pod, enable the engines and create the policy + role:

```bash
vault secrets enable transit
vault auth enable approle
vault policy write digit-transit - <<'EOF'
path "transit/encrypt/*" { capabilities = ["create","update"] }   # create => per-tenant keys auto-create
path "transit/decrypt/*" { capabilities = ["update"] }
EOF
vault write auth/approle/role/individual token_policies=digit-transit token_ttl=1h token_max_ttl=4h

# print the credentials the services will use, then `exit` the pod.
# NOTE: every -f secret-id call GENERATES A FRESH secret-id — run it once and save that value
vault read -field=role_id  auth/approle/role/individual/role-id      # -> sops: cluster-configs.secrets.vault-approle.role-id
vault write -f -field=secret_id auth/approle/role/individual/secret-id  # -> ...vault-approle.secret-id
```

Back on the workstation, store both values in the sops file and re-sync
cluster-configs so the `vault-approle` k8s secret is (re)rendered:

```bash
sops environments/azure-k3s-secrets.yaml   # set cluster-configs.secrets.vault-approle: role-id / secret-id
(cd charts/digit3 && ./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync)
```

**Wire the services**: the `vault-approle` secret feeds
`VAULT_ROLE_ID`/`VAULT_SECRET_ID` and `VAULT_HOST` comes from
`egov-service-host.vault`; flip `VAULT_ENABLED: "true"` in the
service's env and roll it (secret env resolves at pod start, so
already-running pods need a `kubectl rollout restart`). `HMAC_SECRET`
must be non-empty — the service fails closed at boot otherwise (the
mobile-number blind index must be keyed).

**Verify**: create an individual with a mobile number; the API returns
plaintext, while the DB column holds `vault:v1:…` and
`vault list transit/keys` shows a key named after the tenant (auto-created
on first encrypt). Prerequisite: individual-id generation needs an idgen
template registered for the tenant first — otherwise the create fails with
`idgen returned status=404 "template not found"`:

```bash
curl -X POST http://<dev-bundle>:8080/idgen/v3/template \
  -H 'Content-Type: application/json' -H 'X-Tenant-ID: <TENANT>' -H 'X-User-ID: admin' \
  -d '{"templateCode":"individual","config":{"template":"IND-{DATE:yyyy}-{SEQ}",
       "sequence":{"scope":"GLOBAL","start":1,"padding":{"length":6,"char":"0"}}}}'
```

---

## 2. The manifest: how a deployment shape is declared

Skip this section for configuration 1 (per-service needs no bundler). For
everything else, the shape's `digit3/src/bundles/<shape>.package.yaml` is the
single source of truth, with two sections:

- **`services:` — the catalog.** A map keyed by service name holding each
  service's composition-invariant facts (module path, GAV, `packageRoot`,
  `prefix` = its standalone context path, `basePathKey`, `schemaTable`,
  optional knobs). Declared exactly once; bundles reference names, never
  restate facts.
- **`bundles:` — the compositions.** A list; each entry is one JVM with its
  own identity/port/`outputDir`, an **ordered** `include:` list of catalog
  names (order = tenant-migration order; keep `boundary` last — PostGIS
  fail-fast), and its own `overrides:` (loopback hosts for co-bundled
  callers, conflict resolutions, shared-infra properties).

From one manifest, `generate_bundle.py` regenerates **every** listed bundle:
pom (plain-jar deps), main class, path-prefix config, property chain, the
private db-migration tree + combined init image, and a **self-contained app
Dockerfile** (build context = repo root; compiles the whole dependency
closure from the checkout — no Nexus for in-repo jars, version-locked by
construction). Catalog services in no bundle are reported as "run standalone"
— that's a designed mode, not an error.

Cross-bundle calls (a service calling one in *another* bundle) are
env-parameterized in the caller bundle's `overrides:` —
`${<OTHER>_BUNDLE_HOST:http://<other-bundle>.egov.svc.cluster.local:8080}` —
defaulting to cluster DNS, same convention as the services' own hosts.
Note all current bundles use **port 8080** (ports are namespace-scoped in
k8s; earlier dev-bundle builds used 8085).

**Kong follows the manifest too**: `setup.py` reads it by default and derives
each included service's upstream as
`http://<bundle.name>.egov.svc.cluster.local:<bundle.port>`, ensures each
`prefix` is among the route paths, and leaves any service in no bundle on its
per-service DNS. Routes and plugins never change between shapes — no kong
image rebuild, ever.

---

## 3. Configuration 1 — every service separately (no bundler)

One helm release per service, each a thin values-wrapper over the `common`
library chart. The bundler and manifest play **no part** in this shape.

The services helmfile in this shape lists one release per service (idgen-java,
billing-java, … 16 in all) plus keycloak and gateway-kong — each release is
the same 8-line pattern:

```yaml
  - name: idgen-java
    chart: ./idgen-java
    namespace: egov
    installed: true
    missingFileHandler: Warn
    values:
      - ../../environments/azure-k3s-secrets.dec.yaml
      - ../../environments/azure-k3s.yaml
      - ./idgen-java/values.yaml
```

Deploy and program kong (note `KONG_BUNDLE_MANIFESTS=none` — otherwise
setup.py defaults to the repo's manifest and repoints upstreams at bundles):

```bash
./deploy.sh -f digit3services-helmfile.yaml sync
kubectl get pods -n egov     # ~16 service pods + keycloak + kong, all Running

kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd digit3/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> \
  KONG_BUNDLE_MANIFESTS=none python3 setup.py
```

Ordering baked into the helmfile: keycloak first, `account-java`
`needs: [keycloak/keycloak]`; chart paths are explicit (`chart: ./idgen-java`)
because helmfile v1 only templates `*.gotmpl` files.

---

## 4. Configuration 2 — single modulith (`dev-bundle`)

Everything in one JVM (~0.5 GB instead of ~5 GB). Manifest: the `modulith`
branch [`dev-bundle.package.yaml`](https://github.com/digitnxt/digit3/blob/modulith/src/bundles/dev-bundle.package.yaml)
— one `dev-bundle` entry including all 16 catalog services.

### 4.1 Generate and build (workstation)

```bash
cd digit3
python3 src/bundles/generate_bundle.py src/bundles/dev-bundle.package.yaml
# must print "no unresolved property conflicts" — never ignore that warning

# app + db images, the official way (generated Dockerfile, repo root context):
TAG=modulith-$(git rev-parse --short HEAD)
docker buildx build --platform linux/amd64 --load -t egovio/dev-bundle:$TAG \
  -f src/bundles/dev-bundle/Dockerfile .
docker buildx build --platform linux/amd64 --load -t egovio/dev-bundle-db:$TAG \
  src/bundles/dev-bundle/src/main/resources/db
```

(CI equivalent: dev-bundle is registered in `build/build-config.yml` and the
GitHub Actions dropdown — it builds the same pair.)

Load into single-node k3s without a registry (`pullPolicy: IfNotPresent`):

```bash
docker save egovio/dev-bundle:$TAG    | ssh -i <key> azureuser@<domain> 'sudo k3s ctr images import -'
docker save egovio/dev-bundle-db:$TAG | ssh -i <key> azureuser@<domain> 'sudo k3s ctr images import -'
```

### 4.2 Chart + database + environment

```bash
# bundle chart (in this repo): merges the member charts' env/init containers
cd DIGIT-DevOps/deploy-as-code/helm/bundler
python3 generate_bundle_chart.py --manifest <digit3>/src/bundles/dev-bundle.package.yaml
# → charts/bundles/dev-bundle ; read the generation report (dropped/resolved/UNRESOLVED)

# the bundle owns its own database
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -c "CREATE DATABASE bundle_db"
```

`environments/azure-k3s.yaml` needs a `dev-bundle:` block: image tags +
`pullPolicy: IfNotPresent`; env overrides `DB_NAME: bundle_db` (egov-config's
db-name is the per-service DB), `TENANT_MIGRATION_ENABLED: "true"`,
`VAULT_ENABLED: "false"` (no Vault here — otp's client crash-loops the JVM
otherwise), `KEYCLOAK_PUBLIC_BASE_URL`, minio-backed S3
(`S3_ACCESS_KEY`/`S3_SECRET_KEY` from the `minio` secret,
`S3_ENDPOINT: minio.backbone.svc.cluster.local:9000`, `S3_USE_SSL: "false"`);
`dbMigrationOrder: [combined]` with one `dbMigrations.combined` entry using
`dev-bundle-db:<TAG>` and `DB_URL` pointing at `bundle_db`. Also repoint the
bundled services' `egov-service-host` keys at
`http://dev-bundle.egov.svc.cluster.local:8080/`.

The services helmfile carries one `dev-bundle` release (plus keycloak
and gateway-kong).

### 4.3 Deploy, program kong, migrate a tenant

```bash
cd deploy-as-code/helm/charts/digit3
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync  # service-host update
./deploy.sh -f digit3services-helmfile.yaml sync
kubectl get pods -n egov -l app=dev-bundle    # init container migrates, then 1/1 Running

# kong: NO flags — the manifest is the default input
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd digit3/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> python3 setup.py

# tenant migration (endpoint deliberately NOT routed through kong; run in-cluster)
BIP=$(kubectl get svc dev-bundle -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> \
  "curl -s -w '%{http_code}' -X POST http://$BIP:8080/internal/migrate -H 'X-Tenant-ID: DEMO'"
# tenant codes are validated UPPERCASE by the account service
```

Verify: every prefix through kong returns 401 (JWT rejecting anonymous),
`/keycloak` 303; `kubectl top pod` shows the whole platform in one ~450 Mi pod.

---

## 5. Configuration 3 — domain bundles (4 containers)

Same mechanics as configuration 2, N times. Manifest: the `modulith` branch
[`domain-split.package.yaml`](https://github.com/digitnxt/digit3/blob/modulith/src/bundles/domain-split.package.yaml)
— four `bundles:` entries (identity, notification, billing, admin) covering
the whole catalog, each service in exactly one. All on port 8080 (a bundle is
just a bigger pod; ports are namespace-scoped).

What changes versus the single modulith:

- **Generate once, get four modules** — `generate_bundle.py` on that manifest
  emits all four bundle modules, each with its own jar, Dockerfile, and
  combined db-init image. Build/import four image pairs.
- **Cross-bundle calls** are pre-wired in each bundle's `overrides:` as
  `${<OTHER>_BUNDLE_HOST:…}` envs defaulting to the other bundles' cluster
  DNS — in-cluster they work with **no extra env**; override only for
  unusual layouts.
- **Charts**: run `generate_bundle_chart.py` per bundle (the manifest has four
  `bundles:` entries, so pass `--bundle <name>` on each run) → four charts under
  `charts/bundles/`; four release entries in the helmfile; four env blocks in
  `azure-k3s.yaml` (each with its own image tags and combined-init
  `dbMigrations` entry — they can share `bundle_db`).
- **Every bundle needs `TENANT_MIGRATION_ENABLED: "true"`** — each consumes
  tenant-create events and migrates only its own services' tables (a tenant
  is complete only when all four have consumed it).
- **Kong**: nothing new — the same `python3 setup.py` reads the same manifest
  and derives four upstreams, one per bundle, from `bundle.name` +
  `bundle.port`.

---

## 6. Custom combinations, peeling, re-absorbing

The three stock configurations are just points on a spectrum — the manifest
accepts any partition of the catalog:

- **Move a service between bundles / regroup**: edit the `include:` lists,
  regenerate, rebuild the affected bundles' images + charts, sync, rerun
  setup.py. The generator refuses nothing except a service in two bundles.
- **Peel one service out to run standalone** (executed for billing; full
  war story on branch `modulith-separate-billing`): remove its name from
  `include:`; if co-bundled callers reached it over loopback, re-declare
  those hosts env-overridable in `overrides:` (callers' own defaults are
  often literal `localhost`); regenerate; update the bundle's hand-written
  tests to *pin the absence*. Then on the deploy side:
  - build the standalone service's app **and db images from the same source
    tree** — an externally-pinned db image will fail Flyway checksum
    validation against the history the bundle already applied;
  - its chart values: datasource + init `DB_URL` → **`bundle_db`** (its data
    lives there), and **`TENANT_MIGRATION_ENABLED: "true"`** (per-service
    charts ship it false; standalone it must consume tenant events itself);
  - re-add its helmfile release; revert its `egov-service-host` key;
  - **sync the bundle BEFORE the standalone service** (the ingress admission
    webhook rejects a duplicate path while the old bundle Ingress still owns
    it; helmfile syncs concurrently — use `-l` selectors), and rollout-restart
    consumers of changed `egov-service-host` keys (configMapKeyRef env
    resolves at pod start);
  - rerun `setup.py` — the service is in no bundle now, so its upstream
    reverts to per-service DNS automatically.
- **Re-absorb**: the exact mirror — add the name back to `include:`,
  regenerate, uninstall the standalone release, sync the bundle, rerun
  setup.py.

Switching whole shapes is uninstall + sync (the shapes clash on ingress
paths, so remove the old one's releases first) + rerun setup.py with the
matching manifest (or `none`). Data note: bundles use `bundle_db`; the
per-service shape uses the `postgres` DB — independent datasets, so switching
does not migrate data.

---

## 7. Gotchas index (hard-won, all encountered on this install)

| Symptom | Cause / fix |
|---|---|
| `helmfile apply` → "unknown command diff" | helm-diff broken on helm v4 → use `sync` |
| Services helmfile installs nothing, URL-encoded chart path | helmfile v1 templates only `*.gotmpl` → explicit chart paths |
| Secret lands in only one namespace | `---` must be *inside* `{{- range $ns }}` in cluster-configs secret templates |
| Kafka clients: broker DNS never resolves | Kafka release name must be `release-name` (matches egov-config `kafka-brokers`) |
| kong-migration: "failed to parse host name host:5432" | `db-host` in egov-config must be host-only |
| kong: `mkdir /kong: read-only` / permission denied | `readOnlyRootFilesystem: false` + `env.prefix: /kong_prefix` (key appears twice in values — the later one wins) |
| "Tag is mandatory" / `-db:latest` pull errors | every release block in the env file must pin image + init tags |
| `Init:ImagePullBackOff` on a tag that "should" exist | compare the failing ref against `k3s ctr images ls` on the node — e.g. the `db` belongs in the repository (`dev-bundle-db:<tag>`), never in the tag |
| Bundle pod `CreateContainerConfigError: secret "egov-filestore" not found` | chart default is AWS S3 → override S3 env to the minio secret |
| Bundle boot: `NumberFormatException: "15m000"` | Go-duration `DB_CONN_MAX_LIFETIME=15m` harvested into env; dropped via bundler merge-rules |
| Bundle crash-loop in `VaultAuth` | `VAULT_ENABLED=true` harvested; override to `false` (no Vault deployed) |
| Rendered Ingress "apiVersion not set" | generator template `{{- if … -}}` swallowed the line — fixed in `generate_bundle_chart.py` |
| 400 `MISSING_HEADER` on every request | DIGIT 3.x requires `X-Tenant-ID` (+ `X-User-ID` for writes); kong injects them from the JWT in production |
| Tenant code rejected with 400 ValidationFailed | account service requires UPPERCASE tenant codes |
| Tenant schema missing one service's tables | that service's JVM has `TENANT_MIGRATION_ENABLED=false` — every bundle AND every standalone service must consume tenant-create events |
| Standalone service init: "Migration checksum mismatch" | externally-built db image ≠ the copies the bundle applied; build from the same source tree |
| Ingress webhook: "path /X is already defined in ingress …" | two shapes publishing one path; sync the bundle before the standalone service, use `-l` selectors |
| Pod calls old upstream after `egov-service-host` change | `configMapKeyRef` env resolves at pod start → rollout-restart consumers |
| `kubectl port-forward` hangs/000 over the SSH tunnel | curl ClusterIPs from the VM over SSH instead |
| `bind :16443: Address already in use` on tunnel setup | old tunnel still bound; test kubectl first, else `pkill -f "16443:127.0.0.1:6443"` and reconnect |
| `kubectl`: `connection refused` on `127.0.0.1:6443` | kubeconfig still has the k3s default port; edit `server:` to `https://127.0.0.1:16443` (the tunnel port) — see §1.3 |
| Vault pod Pending, PVC stuck | test-lts chart copy pinned `storageClass: gp2` (AWS) → null it for the default SC; volumeClaimTemplates are immutable — uninstall + delete PVC before re-sync |
| Vault: "error fetching AWS KMS wrapping key" | `seal "awskms"` stanza in the copied server config → remove it (Shamir seal; manual unseal after every restart) |
| Vault statefulset change not rolling out | chart uses `OnDelete` update strategy → delete the pod to pick up spec changes |
| Vault unseal command hangs with no output | the in-pod `read -r K` is waiting for the key on stdin → pipe it in (`jq -r '.unseal_keys_b64[0]' init.json \| kubectl exec -i …`) — see the Init + unseal section |
| Vault unseal: `cipher: message authentication failed` | key in the sops file is from an older init — Vault was re-initialized (e.g. fresh PVC) → update `vault-operator:` in the sops file from the new init.json |
| Service crash-loops in `VaultAuth` at boot | `VAULT_ENABLED=true` with unreachable Vault or empty role/secret ids — the client logs in eagerly |
| Vault login 500 "failed to determine alias name" | AppRole login sent an empty role_id — the env override didn't reach the pod; check `kubectl get deploy … -o yaml` for empty `VAULT_ROLE_ID` |
| Keycloak crash-loops: `password authentication failed for user "keycloak"`; tenant create fails with `failed to get admin token: ConnectException` | the `keycloak` Postgres role from §1.7 was never created (the DB alone isn't enough) → create it from the kc-db secret, delete the Keycloak pod |
| Bundle env `valueFrom` override renders as empty env var | chart default `value: ""` shadowed the `valueFrom` (the `common.name` mergo merge can't delete keys, `null` included) — fixed in the generator: non-empty `value` wins, else `valueFrom`; regenerate the bundle chart |
| New pods fail DB auth after a cluster-configs sync | the repo's sops secrets diverged from what the cluster was deployed with — cluster-configs re-rendered secrets over live ones; reconcile the sops file with the cluster before syncing |
