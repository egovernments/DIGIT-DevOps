# DIGIT 3 on single-node k3s — full replication guide

> **Installing?** The one-command path is [ONE-STEP-INSTALL.md](ONE-STEP-INSTALL.md);
> the phase-by-phase runbook is [INSTALLATION-STEPS.md](INSTALLATION-STEPS.md).
> Both drive the idempotent `scripts/` pipeline. This document is the
> reference *behind* them — what each step does, and the troubleshooting table.

DIGIT 3 has no fixed deployment shape: **which services share a JVM is declared
in one manifest per shape** (`src/bundles/<shape>.package.yaml` in the digit3
repo), and every layer — the bundle jars, their Docker images, the helm
charts, and Kong's routing — is derived from it. Any grouping of the 16 core
services is a valid deployment. Out of the box, three are provided (deployed on
`modulith.digit.org`, an 8 vCPU / 32 GB / 100 GB Ubuntu 22.04 VM):

| `--shape` | Configuration | Containers | Helmfile | Manifest (digit3 `modulith`) |
|---|---|---|---|---|
| `single-container` | everything in one JVM (`dev-bundle`, ~430 Mi) | 1 | `single-container-helmfile.yaml` | `src/bundles/dev-bundle.package.yaml` |
| `domain-bundles` | four JVMs along building-block lines | 4 | `domain-bundles-helmfile.yaml` | `src/bundles/domain-split.package.yaml` |
| `per-service` | every service its own pod | 16 | `per-service-helmfile.yaml` | none (charts served directly) |

`domain-bundles` grouping: `identity-bundle` (otp, individual, employee,
account) · `notification-bundle` (template-config, notification, url-shortener)
· `billing-bundle` (billing, apportion, pg-service) · `admin-bundle` (idgen,
localization, workflow, registry, filestore, boundary). See
[BUNDLING.md](./BUNDLING.md) for how a bundle works internally, and
[CUSTOM-BUNDLING.md](./CUSTOM-BUNDLING.md) for a non-stock grouping.

Each shape's domain and `egov-service-host` keys come from its overlay
(`environments/azure-k3s-<shape>.yaml`), layered by its helmfile; image tags
come from `DIGIT_TAG`. All three sit on the **same foundation** (Section 1);
deploy exactly ONE at a time (they share ingress paths and kong prefixes) —
switching is Section 6. (The pre-rename names `dev-bundle` / `domain-split` /
`services` are still accepted as shape synonyms.)

Repos used (both on the `modulith` branch):

| Repo | Role |
|---|---|
| `DIGIT-DevOps` | helm charts (`charts/digit3`, `charts/bundles/dev-bundle`), environments, bundler chart generator |
| `digit3` | service source, bundle generator (`src/bundles/`), kong bootstrap (`src/services/kong/setup.py`) |

Workstation prerequisites: `kubectl`, `helm` (v4 tested), `helmfile` (v1.7+),
`sops` + `age`, `docker` (with buildx), JDK 25 (Temurin), Maven 3.9+,
`python3` with `pyyaml` and `requests`.

---

## 1. Common foundation (required for ALL shapes)

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
which later gives the ingress-nginx LoadBalancer service the node's IP on
80/443. No extra storage or LB setup needed.

### 1.3 kubeconfig over an SSH tunnel

If 6443 is not open in the NSG (recommended), tunnel it:

```bash
# on the workstation — re-run after VM reboots or if kubectl starts timing out
ssh -f -N -L 16443:127.0.0.1:6443 -i <key> azureuser@<domain>
# "Address already in use" → a tunnel exists; test kubectl, and if stale:
#   pkill -f "16443:127.0.0.1:6443"   then re-run the ssh command

ssh -i <key> azureuser@<domain> 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/modulith-kubeconfig.yaml
# edit: server: https://127.0.0.1:16443 ; rename context/cluster/user to `modulith`
export KUBECONFIG=~/modulith-kubeconfig.yaml
kubectl get nodes
```

Keep this kubeconfig in its **own file** (not merged into `~/.kube/config`)
so mutating commands can never accidentally target another cluster.

> `kubectl port-forward` through this tunnel is unreliable for data
> transfer. For in-cluster calls, prefer `ssh <vm> 'curl http://<ClusterIP>:…'`.

### 1.4 Secrets: fresh credentials, encrypted with age

No AWS/KMS dependency. One-time:

```bash
age-keygen -o ~/.config/sops/age/keys.txt        # BACK THIS FILE UP — only key to the secrets
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
- One block per service/release pinning **image tags** (mandatory — chart
  defaults resolve to `:latest` which do not exist).

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
# plus a `keycloak` role with the password from the kc-db secret
```

(Keycloak is installed by every shape's helmfile.)

### 1.8 Optional: HashiCorp Vault (PII encryption at rest)

Services with PII (otp, individual) encrypt fields via Vault's **Transit**
engine — stored as `vault:v1:…` ciphertext with a keyed HMAC blind index for
search, one transit key **per tenant** (auto-created on first encrypt).
Everything runs with `VAULT_ENABLED=false` until you flip it in the
environment file (the dev-bundle and identity-bundle blocks in azure-k3s.yaml
ship it ON; the chart defaults already carry the `vault-approle` /
`hmac-secret` secretKeyRefs, rendered by cluster-configs from the sops file).

The chart is `charts/digit3/vault` (official HashiCorp 0.29.1, de-AWS'd:
no gp2 storageClass, no awskms auto-unseal, no public ingress; release name
and namespace MUST be `vault` — egov-config's `vault-host` and
egov-service-host's `vault` keys point there). One idempotent script deploys,
initializes (1-of-1 Shamir, keys written straight into the sops file),
unseals, enables transit + AppRole (`digit-services` role, `digit-transit`
policy covering encrypt/decrypt/sign/verify/keys + token renew-self) and
renders the `vault-approle` secret:

```bash
scripts/04-vault.sh        # needs scripts/.env: SSH_KEY, DOMAIN, KUBECONFIG_PATH
```

**After every Vault pod restart the Shamir seal closes** — re-run the script
(it detects the initialized state and just unseals from the sops file). PII
encrypt/decrypt calls fail while sealed; the services themselves stay up.

---

## 2. The manifest: how a deployment shape is declared

Skip this for `per-service` (it needs no bundler). For the bundle shapes, the
shape's `digit3/src/bundles/<name>.package.yaml` is the single source of truth,
with two sections:

- **`services:` — the catalog.** A map keyed by service name, deliberately
  minimal: only `module` (path under `src/`) and `packageRoot` are stated.
  Maven coordinates are DERIVED from the module's pom; `contextPath` (`/<name>`),
  `basePathKey` (`<name>.base-path`) and `schemaTable` (`<name>_schema`) follow
  conventions, stated only for a deviation. `publicSchemaTable` marks a
  public-only service (account); `publicMigrationDirs` picks the init
  container's Flyway dirs. Bundles reference catalog names — never restating a
  service's facts, so they can't drift between shapes.
- **`bundles:` — the compositions.** A list; each entry is one JVM with its own
  identity/port/`outputDir`, an **ordered** `include:` of catalog names (order =
  tenant-migration order; keep `boundary` last — its PostGIS migration
  fail-fasts on an extension-less DB), and its own `overrides:` (loopback hosts
  for co-bundled callers, conflict resolutions, shared-infra properties).

From one manifest, `generate_bundle.py` regenerates **every** listed bundle:
the pom (plain-jar deps), main class, path-prefix config, the property chain,
the private db-migration tree + combined init image, and a self-contained app
Dockerfile (build context = repo root; compiles the member closure from the
checkout, platform libs from Nexus — version-locked by construction). A catalog
service in no bundle is reported as "runs standalone" — a designed mode, not an
error.

Cross-bundle calls are env-parameterized in the caller's `overrides:` as
`${<OTHER>_BUNDLE_HOST:http://<other-bundle>.egov.svc.cluster.local:8080}`,
defaulting to cluster DNS — in-cluster they need no extra env. All bundles use
port 8080 (namespace-scoped in k8s).

**Kong follows the manifest too**: `setup.py` reads it and derives each member's
upstream as `http://<bundle.name>.egov.svc.cluster.local:<bundle.port>`, ensures
each context path is a route, and leaves any unbundled service on its
per-service DNS. Routes and plugins never change between shapes — no kong image
rebuild.

---

## 3. `single-container` — the modulith bundle

The `modulith` branch helmfile is already in this shape:
`single-container-helmfile.yaml` contains keycloak, **dev-bundle** and
gateway-kong (authorization is Keycloak itself — kong's keycloak-rbac
plugin; the former accesscontrol service is no longer deployed).

### 3.1 Build the bundle jar (workstation)

```bash
cd digit3 && export JAVA_HOME=<jdk25>

# publish the platform libraries + every bundled service's PLAIN jar to ~/.m2
(cd src/libraries/tracer && mvn install)
(cd src/libraries/tenant-migration && mvn install)
for s in idgen billing apportion url-shortener pg-service otp notification employee \
         individual workflow registry filestore localization account boundary; do
  (cd src/services/$s && mvn install -DskipTests)
done
(cd src/utilities/template-config && mvn install -DskipTests)

# generate + build the bundle — generator must print "no unresolved property conflicts"
python3 src/bundles/generate_bundle.py src/bundles/dev-bundle.package.yaml
(cd src/bundles/dev-bundle && mvn clean package -DskipTests)
```

*(Optional but recommended once per code change: verify locally against a
local Postgres+Redis — `mvn clean test`, run the jar, smoke with
`X-Tenant-ID`/`X-User-ID` headers. Full local recipe:
`digit3/src/bundles/README.md`.)*

### 3.2 Build linux/amd64 images and load them into k3s (no registry)

```bash
mkdir /tmp/bundle-image && cp src/bundles/dev-bundle/target/dev-bundle-*.jar /tmp/bundle-image/app.jar
cat > /tmp/bundle-image/Dockerfile <<'EOF'
FROM amazoncorretto:25
WORKDIR /opt/egov
COPY app.jar /opt/egov/app.jar
EXPOSE 8080
CMD ["sh", "-c", "exec java $JAVA_OPTS -jar /opt/egov/app.jar"]
EOF
TAG=modulith-$(git -C digit3 rev-parse --short HEAD)
docker buildx build --platform linux/amd64 --load -t egovio/dev-bundle:$TAG /tmp/bundle-image
docker buildx build --platform linux/amd64 --load -t egovio/dev-bundle-db:$TAG \
  digit3/src/bundles/dev-bundle/src/main/resources/db

# straight into the node's containerd (single-node k3s; pullPolicy IfNotPresent)
docker save egovio/dev-bundle:$TAG    | ssh -i <key> azureuser@<domain> 'sudo k3s ctr images import -'
docker save egovio/dev-bundle-db:$TAG | ssh -i <key> azureuser@<domain> 'sudo k3s ctr images import -'
```

### 3.3 Bundle chart + database + environment

```bash
# regenerate the bundle chart if the manifest changed (committed output: charts/bundles/dev-bundle)
cd DIGIT-DevOps/deploy-as-code/helm/bundler
python3 generate_bundle_chart.py --manifest <digit3>/src/bundles/dev-bundle.package.yaml
```

No database prep: the bundle uses the cluster's **default `postgres`
database** (same as the per-service shape) — tenant data separates by
schema, not by database.

`environments/azure-k3s.yaml` needs (already present on this branch — update
the two `tag:` values to your `$TAG`):

- a **`dev-bundle:` block**: image `dev-bundle:<TAG>` +
  `pullPolicy: IfNotPresent`; env overrides
  `TENANT_MIGRATION_ENABLED: "true"`, `VAULT_ENABLED: "false"` (no Vault
  here — otp's client crash-loops the JVM otherwise),
  `KEYCLOAK_PUBLIC_BASE_URL`, `URL_SHORTENER_HOST_NAME` (the generated
  chart bakes the harvest-time host), and minio-backed S3
  (`S3_ACCESS_KEY`/`S3_SECRET_KEY` from the `minio` secret,
  `S3_ENDPOINT: minio.backbone.svc.cluster.local:9000`,
  `S3_USE_SSL: "false"`); `dbMigrationOrder: [combined]` with one
  `dbMigrations.combined` entry using `dev-bundle-db:<TAG>` and `DB_URL`
  pointing at the default `postgres` database.
- **`egov-service-host`** keys of the 13 merged services →
  `http://dev-bundle.egov.svc.cluster.local:8080/`.

Both of the above (domain + service-host keys) live in the per-shape overlay
files — `environments/azure-k3s-{services,dev-bundle,domain-split}.yaml` —
layered by each shape's helmfile after the shared base `azure-k3s.yaml`.
Switching shape = syncing the other shape's helmfile (then the
cluster-configs sync below and a rollout restart of consumers). Image tags
are not in any values file: every digit3 image is tagged from the `DIGIT_TAG`
environment variable (`environments/digit-tag.yaml.gotmpl`) and the deploy
fails loudly when it is unset.

### 3.4 Deploy

```bash
cd deploy-as-code/helm/charts/digit3
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync  # service-host update
DIGIT_TAG=modulith-<sha> ./deploy.sh -f single-container-helmfile.yaml sync   # keycloak, dev-bundle, kong
kubectl get pods -n egov -l app=dev-bundle   # init container migrates public schema, then 1/1 Running
```

### 3.5 Program kong (bundle upstream)

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd digit3/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> python3 setup.py
```

By default `setup.py` reads the repo's `dev-bundle.package.yaml` and repoints
every bundled service's kong upstream at its bundle's Service
(`http://<bundle>.<ns>:<port>`, overridable per bundle with
`KONG_BUNDLE_UPSTREAM_<NAME>`); keycloak keeps its own. Set
`KONG_BUNDLE_MANIFESTS=none` for per-service upstreams, or point it at
another manifest (the domain-split branch's manifest yields four bundle
upstreams). Routes/plugins are unchanged (strip_path=false + each service's
context path inside the bundle).

### 3.6 Tenant + verify

```bash
# normal path: onboard a tenant through the account API (unprotected bootstrap
# route) — creates the tenant, its Keycloak realm, AND publishes the migration
# event every consumer turns into the tenant's schema:
#   POST /accounts/v3/tenants  {name, email, password, phone(E.164), address, …}
# manual alternative (endpoint deliberately NOT routed through kong; in-cluster):
BIP=$(kubectl get svc dev-bundle -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> \
  "curl -s -w '%{http_code}' -X POST http://$BIP:8080/internal/migrate -H 'X-Tenant-ID: DEMO'"
# tenant codes are validated UPPERCASE by the account service

KIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> \
  "curl -s -o /dev/null -w '%{http_code}' -H 'Host: <domain>' http://$KIP:8000/idgen/"
# every bundled prefix → 401 (JWT), /keycloak → 303
kubectl top pod -n egov -l app=dev-bundle    # ~600Mi for all 16 services
```

---

## 4. `per-service` — each service its own pod

This is the pre-bundle shape of `single-container-helmfile.yaml`: one release
per service (idgen, billing, …, 16 in all) plus keycloak and
gateway-kong. On the `modulith` branch those 16
entries were replaced by `dev-bundle` — to deploy per-service, check out the
helmfile from the commit before the bundle cutover (or re-add the release
entries; each is the same 8-line pattern):

```yaml
  - name: idgen
    chart: ./idgen
    namespace: egov
    installed: true
    missingFileHandler: Warn
    values:
      - ../../environments/azure-k3s-secrets.dec.yaml
      - ../../environments/azure-k3s.yaml
      - ./idgen/values.yaml
```

This shape has its own helmfile — `per-service-helmfile.yaml` (keycloak, the
16 services, kong) — which layers `environments/azure-k3s-per-service.yaml`
(domain + the 13 per-service `egov-service-host` keys) and takes its image
tags from `DIGIT_TAG`, like the other shapes:

```bash
DIGIT_TAG=modulith-<sha> ./deploy.sh -f per-service-helmfile.yaml sync
```

### 4.1 Deploy

```bash
cd deploy-as-code/helm/charts/digit3
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync  # if service-host changed
DIGIT_TAG=modulith-<sha> ./deploy.sh -f per-service-helmfile.yaml sync
kubectl get pods -n egov     # expect ~16 service pods + keycloak + kong, all Running
```

Notes baked into the helmfile: keycloak first; `account` has
`needs: [keycloak/keycloak]`; chart paths are explicit
(`chart: ./idgen`) because helmfile v1 only templates `*.gotmpl` files.

### 4.2 Program kong (per-service upstreams)

Same script, just **without** `KONG_BUNDLE_UPSTREAM` — upstreams then point
at the per-service k8s Services (`http://idgen.egov.svc.cluster.local:8080`, …):

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd digit3/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> python3 setup.py
```

### 4.3 Verify

```bash
kubectl get pods -A          # everything Running
KIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> \
  "curl -s -o /dev/null -w '%{http_code}' -H 'Host: <domain>' http://$KIP:8000/idgen/"  # 401
ssh -i <key> azureuser@<domain> \
  "curl -s -o /dev/null -w '%{http_code}' -H 'Host: <domain>' http://$KIP:8000/keycloak" # 303
```

---

## 5. `domain-bundles` — four JVMs (identity / notification / billing / admin)

Same mechanics as single-container, four times. Manifest: the `modulith` branch
[`domain-split.package.yaml`](https://github.com/digitnxt/digit3/blob/modulith/src/bundles/domain-split.package.yaml)
— four `bundles:` entries covering the whole catalog, each service in exactly
one, all on port 8080. Grouping: `identity-bundle` (otp, individual, employee,
account) · `notification-bundle` (template-config, notification, url-shortener)
· `billing-bundle` (billing, apportion, pg-service) · `admin-bundle` (idgen,
localization, workflow, registry, filestore, boundary).

What differs from single-container:

- **One generate, four modules** — `generate_bundle.py` on that manifest emits
  all four bundle modules (jar + Dockerfile + combined db-init each). The images
  are already published; build four pairs with `05-build.sh` only for your own
  code.
- **Cross-bundle calls** are pre-wired in each bundle's `overrides:` as
  `${<OTHER>_BUNDLE_HOST:…}` defaulting to the other bundles' cluster DNS — no
  extra env in-cluster.
- **Charts**: `generate_bundle_chart.py --manifest domain-split.package.yaml`
  regenerates all four in ONE run (no per-bundle flag) → four charts under
  `charts/bundles/`. `domain-bundles-helmfile.yaml` already lists the four
  releases; `azure-k3s-domain-bundles.yaml` carries their env blocks and the
  service-host map.
- **Every bundle runs `TENANT_MIGRATION_ENABLED: "true"`** — each consumes the
  tenant-create event under its own consumer group and migrates only its own
  services' tables; a tenant is complete only when all four have consumed it.
- **Kong**: nothing new — `setup.py` with `KONG_BUNDLE_MANIFESTS=<manifest>`
  derives four upstreams, one per bundle.

Deploy it exactly like the other shapes:

```bash
DIGIT_TAG=<tag> ./deploy.sh -f domain-bundles-helmfile.yaml sync
# equivalently: ./scripts/06-deploy.sh <digit3> domain-bundles <tag>
```

---

## 6. Switching between shapes

The shapes are mutually exclusive (same ingress paths, same kong prefixes).
Data note: both shapes use the default `postgres` database and the same
per-tenant schemas, so the data carries across a shape switch. (Historic
deployments gave the bundle its own `bundle_db`; that override is gone.)

**B → A (services → bundle)** — the order matters, remove services first:

```bash
for r in account apportion billing boundary employee filestore \
         idgen individual localization notification otp pg-service \
         registry template-config url-shortener workflow; do
  helm uninstall "$r" -n egov
done
# then follow §3 (single-container) from 3.3 (env/service-host) → 3.4 sync → 3.5 kong repoint
```

**A → B (bundle → services)**:

```bash
helm uninstall dev-bundle -n egov
# restore the 16 release entries in the helmfile + per-service egov-service-host keys,
# then §4 (per-service) 4.1 sync → 4.2 setup.py WITHOUT KONG_BUNDLE_UPSTREAM
```

Finally (either shape): open NSG 80/443 → the `cm-acme-http-solver` pods
complete, certificates issue, and `https://<domain>/<service>` works
publicly.

---

## 7. Peeling one service out of the bundle (worked example: billing)

Sometimes one service needs to scale, fail, or release independently while the
rest stay bundled. The design makes the *jar* side trivial ("remove the
manifest entry and regenerate"), but a full deployment peel touches five
layers. This section is the generic procedure; the executed billing peel
lives on branch **`modulith-separate-billing`** in both repos (DIGIT-DevOps
`05e09c83d`, digit3 `52a570c0`) — every referenced change can be read there
verbatim.

### 7.1 digit3: manifest + overrides + tests

- Delete the service's name from its bundle's `include:` list in
  its composition manifest (the catalog entry stays).
- Prune `overrides:`: the service's own loopback hosts go away, and — the
  subtle one — overrides that pointed **other services at it** over loopback
  must become network-reachable. Check the callers' own defaults first: if
  they are literal (`billing.host=http://localhost:8080/`, no `${…}`), the
  bundle must re-declare them env-overridable, e.g.
  `billing.host: "${BILLING_HOST:http://localhost:8080}/"`.
- Regenerate (`generate_bundle.py`) — expect "no unresolved property
  conflicts".
- **Update the hand-written tests** (`src/test/` survives regeneration and
  will fail compilation if it references the peeled service's classes). Flip
  its assertions to *absence pins*: its route prefix must NOT be mounted, its
  beans and Jackson customizers must be gone — so an accidental re-inclusion
  fails the build loudly (billing's mapper modules changed every service's
  BigDecimal wire format; silence would be dangerous).
- `mvn clean test && mvn package`.

### 7.2 Images — same source tree for everything (important)

Build and import (§3.2 mechanics) with a new tag: the **bundle pair** AND the
**peeled service's app + db images**, all from the same digit3 checkout:

```bash
# app: runtime-only image from the service's *-exec.jar
# db:  from src/services/<svc>/src/main/resources/db (its own Dockerfile)
```

Do NOT reuse an externally-pinned per-service db image: the billing peel
failed exactly there — the old image carried a different copy of one
migration, and Flyway rejected it against the history the bundle had already
applied to the bundle's database ("Migration checksum mismatch"). Same source tree →
identical files → validation passes.

### 7.3 DIGIT-DevOps: chart, values, env, helmfile

- Rerun `generate_bundle_chart.py` — the peeled service's ingress context and
  `dbMigrations` entry disappear, and the *callers'* harvested env pointing
  at it (`APPORTION_BILLING_HOST`, `BILLING_HOST` ← `egov-service-host` key
  `billing`) automatically **survives** the merge now (loopback
  detection only drops env for bundled services). No manual env plumbing.
- Peeled service's chart values: keep its datasource and db-migration init
  `DB_URL` on the **same database the bundle used** — its public tables,
  Flyway history and tenant schemas live there. With today's default
  (`postgres` for every shape) nothing needs changing; the executed billing
  peel predates that and had to pin `bundle_db` explicitly.
- Tenant migration: the per-service charts now ship
  `TENANT_MIGRATION_ENABLED`/`SCHEMA_SEPARATION_MODE` **true**, so a peeled
  service consumes tenant events out of the box. (The original peel found
  this the hard way: charts then shipped `false`, and creating tenant TEST
  produced 53/72 tables — all 19 missing ones billing's — until the flag was
  set and the consumer replayed the event.)
- `environments/<env>.yaml`: bump the `dev-bundle:` tags; point the peeled
  service's image + init image at the source-built tags
  (`pullPolicy: IfNotPresent` for containerd-imported images); revert its
  `egov-service-host` key from the bundle back to its own Service.
- Helmfile: re-add the service's release entry (its env block was kept).

### 7.4 Deploy — order matters

```bash
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync            # service-host key
DIGIT_TAG=<tag> ./deploy.sh -f single-container-helmfile.yaml -l name=dev-bundle sync   # FIRST: frees /billing
DIGIT_TAG=<tag> ./deploy.sh -f single-container-helmfile.yaml -l name=billing sync      # THEN the peeled service
kubectl rollout restart deploy/dev-bundle -n egov                                     # see below
```

Two traps encoded in that order:

1. The nginx admission webhook rejects the peeled service's Ingress while the
   OLD bundle Ingress still owns its path ("path /billing is already defined
   in ingress egov/dev-bundle") — and helmfile syncs releases concurrently,
   so a plain full sync can race into exactly that. Use `-l` selectors.
2. `configMapKeyRef` env is resolved at **pod start**: if the bundle pod
   started before the `egov-service-host` key changed, its `BILLING_HOST`
   still points at itself. One rollout restart after the cluster-configs
   sync fixes it.

### 7.5 Kong

```bash
KONG_ADMIN_URL=… KONG_ROUTE_HOSTS=<domain> python3 setup.py
```

No extra flags: the peel already removed the service from the manifest's
`include:` list, and `setup.py` derives upstreams from that manifest —
services in no bundle keep (or revert to) their per-service upstreams on
the next run. Route paths never change, so clients notice nothing.

### 7.6 Verify + aftermath

- Bundle: peeled prefix NOT served (expect the 400-coded
  `NoResourceFoundException` envelope — the platform renders 404s that way);
  all other prefixes intact.
- Peeled pod: init container validates cleanly against the shared database; a
  tenant-headered read returns real data (billing: `GET
  /billing/v3/business-services` → 200; demo-tenant tables intact).
- Kong: peeled route → its Service, others → bundle; 401s everywhere, and a
  cross-boundary call works in both directions (bundle→peeled via
  `*_HOST` env, peeled→bundle via the repointed `egov-service-host` keys).
- Going forward: `POST /internal/migrate` on the bundle no longer covers the
  peeled service — it consumes the same tenant-create events itself, but it
  is now a second thing to check when provisioning tenants.

Re-absorbing the service later is the exact mirror: restore the manifest
entry + overrides, regenerate both generators, uninstall its release,
sync the bundle, rerun setup.py without the exclude.

---

## 8. Gotchas index (hard-won, all encountered on this install)

| Symptom | Cause / fix |
|---|---|
| `helmfile apply` → "unknown command diff" | helm-diff broken on helm v4 → use `sync` |
| Services helmfile installs nothing, URL-encoded chart path | helmfile v1 templates only `*.gotmpl` → explicit chart paths |
| Secret lands in only one namespace | `---` must be *inside* `{{- range $ns }}` in cluster-configs secret templates |
| Kafka clients: broker DNS never resolves | Kafka release name must be `release-name` (matches egov-config `kafka-brokers`) |
| kong-migration: "failed to parse host name host:5432" | `db-host` in egov-config must be host-only |
| kong: `mkdir /kong: read-only` / permission denied | `readOnlyRootFilesystem: false` + `env.prefix: /kong_prefix` (key appears twice in values — the later one wins) |
| "Tag is mandatory" / `-db:latest` pull errors | every service block in the env file must pin image + init tags |
| Bundle pod `CreateContainerConfigError: secret "egov-filestore" not found` | chart default is AWS S3 → override S3 env to the minio secret |
| Vault login 500 "failed to determine alias name" | AppRole login sent an empty role_id — the env override didn't reach the pod; check `kubectl get deploy … -o yaml` for empty `VAULT_ROLE_ID` |
| Bundle env `valueFrom` override renders as empty env var | chart default `value: ""` shadowed the `valueFrom` (the `common.name` mergo merge can't delete keys, `null` included) — fixed in the generator: non-empty `value` wins, else `valueFrom`; regenerate the bundle chart |
| Bundle boot: `NumberFormatException: "15m000"` | Go-duration `DB_CONN_MAX_LIFETIME=15m` harvested into env; dropped via bundler merge-rules |
| Bundle crash-loop in `VaultAuth` | `VAULT_ENABLED=true` harvested; override to `false` (no Vault deployed) |
| Rendered Ingress "apiVersion not set" | generator template `{{- if … -}}` swallowed the line — fixed in `generate_bundle_chart.py` |
| 400 `MISSING_HEADER` on every request | DIGIT 3.x requires `X-Tenant-ID` (+ `X-User-ID` for writes); kong injects them from the JWT in production |
| Tenant code rejected with 400 ValidationFailed | account service requires UPPERCASE tenant codes |
| `kubectl port-forward` hangs/000 over the SSH tunnel | curl ClusterIPs from the VM over SSH instead |
| `bind :16443: Address already in use` on tunnel setup | old tunnel still bound; test kubectl first, else `pkill -f "16443:127.0.0.1:6443"` and reconnect |
| Ingress webhook: "path /X is already defined in ingress egov/dev-bundle" | both shapes publish the same path; sync dev-bundle BEFORE the peeled service (helmfile syncs concurrently — use `-l` selectors) |
| Peeled service init: "Migration checksum mismatch" | externally-built db image ≠ the copies the bundle applied; build the service's db image from the same source tree |
| Pod calls old upstream after `egov-service-host` change | `configMapKeyRef` env resolves at pod start → rollout-restart consumers after cluster-configs sync |
