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
`sops` + `age`, `python3` with `pyyaml` and `requests`. Only for building your
own images (§3.1–3.2, `05-build.sh`): `docker` (with buildx), JDK 25 (Temurin),
Maven 3.9+ — the published `egovio/*:modulith-<sha>` images need none of these.

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
# OPTIONAL but recommended — authenticated Docker Hub pulls. The images are
# public, but anonymous pulls are capped at 100/h per IP and one per-service
# install needs 42, so a second install within the hour hits 429. Any Docker
# Hub account with a read-only access token lifts the cap. Write this BEFORE
# installing k3s (it is read at start); k3s-uninstall removes it.
sudo mkdir -p /etc/rancher/k3s && sudo tee /etc/rancher/k3s/registries.yaml >/dev/null <<'EOF'
configs:
  "docker.io":
    auth:
      username: <dockerhub-user>
      password: <read-only-token>
  "registry-1.docker.io":
    auth:
      username: <dockerhub-user>
      password: <read-only-token>
EOF
sudo chmod 600 /etc/rancher/k3s/registries.yaml

curl -sfL https://get.k3s.io | sh -s - --disable traefik
sudo k3s kubectl get nodes    # wait for Ready
```

(`01-cluster.sh` writes the same file from `DOCKERHUB_USER`/`DOCKERHUB_TOKEN`,
`~/.config/digit3/dockerhub.env`, or `install.sh --hub-user/--hub-token`.)

k3s ships `local-path` as the default StorageClass and klipper ServiceLB,
which later gives the ingress-nginx LoadBalancer service the node's IP on
80/443. No extra storage or LB setup needed.

### 1.3 kubeconfig over an SSH tunnel

If 6443 is not open in the NSG (recommended), tunnel it:

```bash
# on the workstation — re-run after VM reboots or if kubectl starts timing out
ssh -f -N -o ExitOnForwardFailure=yes -L 16443:127.0.0.1:6443 -i <key> azureuser@<domain>
# Non-zero exit ("cannot listen to port: 16443") → a tunnel already holds the port.
# Without ExitOnForwardFailure ssh would only warn, exit 0 and leave a useless
# duplicate while the OLD tunnel keeps serving kubectl — possibly another cluster.
# Test `kubectl get nodes`; if it fails or answers for the wrong VM:
#   pkill -f "16443:127.0.0.1:6443"   then re-run the ssh command

ssh -i <key> azureuser@<domain> 'sudo cat /etc/rancher/k3s/k3s.yaml' > ~/modulith-kubeconfig.yaml
# edit: server: https://127.0.0.1:16443 ; rename context/cluster/user to `modulith`
export KUBECONFIG=~/modulith-kubeconfig.yaml
kubectl get nodes
```

Keep this kubeconfig in its **own file** (not merged into `~/.kube/config`)
so mutating commands can never accidentally target another cluster.

Record the connection settings once — `deploy.sh` reads `DOMAIN` to pick the
per-environment secrets file (§1.4), and every `scripts/*.sh` (e.g. §1.8's
`04-vault.sh`) reads all three. On the scripted path `01-cluster.sh` writes it:

```bash
cat > deploy-as-code/helm/charts/digit3/scripts/.env <<EOF
SSH_KEY="<absolute path to the ssh key>"
DOMAIN="<domain>"
VM_USER="azureuser"
KUBECONFIG_PATH="$HOME/modulith-kubeconfig.yaml"
EOF
```

> `kubectl port-forward` through this tunnel is unreliable for data
> transfer. For in-cluster calls, prefer `ssh <vm> 'curl http://<ClusterIP>:…'`.

### 1.4 Secrets: fresh credentials, encrypted with age

No AWS/KMS dependency. One-time — **if `~/.config/sops/age/keys.txt` already
exists, reuse it** (a new key cannot decrypt files encrypted for the old one;
`age-keygen` refuses to overwrite):

```bash
age-keygen -o ~/.config/sops/age/keys.txt        # BACK THIS FILE UP — only key to the secrets
# macOS sops looks elsewhere:
mkdir -p ~/Library/Application\ Support/sops/age
ln -sf ~/.config/sops/age/keys.txt ~/Library/Application\ Support/sops/age/keys.txt
```

The `.sops.yaml` rule `environments/azure\-k3s\-secrets(\..*)?\.yaml$` covers
both the shared file and **per-environment files** — name yours
`environments/azure-k3s-secrets.<domain>.yaml` (e.g.
`azure-k3s-secrets.modulith.digit.org.yaml`). `deploy.sh` and the scripts use
that file whenever `scripts/.env` (§1.3) names the matching `DOMAIN`, so two
clusters never share credentials and §1.8's Vault keys never land in the
tracked shared file. Add your age recipient to the rule if it is not there.
If the file already exists (an earlier install of this environment), reuse
it — its credentials become the new cluster's.

Create the file (same YAML shape as `test-lts-secrets.yaml`:
`cluster-configs.secrets.*` for `db`, `minio`, `kc-db`, `kc-admin`,
`hmac-secret`, `citizen-broker-secret`, `employee-iam-secret`, `kafka-kraft`
`kraft-cluster-id`, `vault-approle` (filled in by §1.8), plus SMTP/SMS/Stripe
placeholders) with fresh generated passwords, and encrypt in place:

```bash
sops -e -i environments/azure-k3s-secrets.<domain>.yaml
```

**`db.password` and `db.flywayPassword` must be the SAME value** — both are
the one `postgres` superuser (there is no separate flyway role). Different
values give every service init container `FATAL: password authentication
failed for user "postgres" (28P01)`. `02-secrets.sh` does all of the above.

`helm-secrets` does not work with helm v4, so `charts/digit3/deploy.sh`
decrypts to `environments/azure-k3s-secrets.dec.yaml` (git-ignored — ensure
`*.dec.yaml` is in `.gitignore`), runs helmfile, and deletes the file on exit.

### 1.5 The environment file

Two layers, both already present on this branch:

- `environments/azure-k3s.yaml` — the **shared base**: `cluster-configs:`
  (namespaces `[backbone, cert-manager, egov, health, keycloak, monitoring,
  playground]`; `egov-config` data — `db-host` must be **host only**, kong
  reads it as `KONG_PG_HOST`; `db-url` the full JDBC URL; `kafka-brokers:
  release-name-kafka-controller-headless.backbone:9092`; root-ingress →
  `kong-kong-proxy:8000`) and one env block per service/bundle (Vault is ON
  here — `vault-enabled: "true"` for otp/individual, `VAULT_ENABLED` for the
  bundles; see §1.8).
- `environments/azure-k3s-<shape>.yaml` — the **per-shape overlay**
  (`per-service`, `single-container`, `domain-bundles`), layered by that
  shape's helmfile: **`global.domain` — set your domain HERE**, plus the
  shape's `egov-service-host` map (which Service answers for each of the 13
  merged services).

Image tags live in **neither** file: every digit3 image (services, bundles and
their `-db` init images) is tagged from the `DIGIT_TAG` environment variable
(`environments/digit-tag.yaml.gotmpl`, `requiredEnv` — the deploy fails
loudly when it is unset). Use a tag the Actions pipeline published for **all**
images, e.g. `modulith-39f619d`.

### 1.6 Deploy the backbone

```bash
cd deploy-as-code/helm/charts/digit3
export KUBECONFIG=~/modulith-kubeconfig.yaml
./deploy.sh -f backboneservices-helmfile.yaml sync
# On a fresh cluster the FIRST sync reliably fails on cert-manager's ClusterIssuer
# ("no endpoints available for service cert-manager-webhook") — expected. Then:
kubectl wait --for=condition=ready pod -l app.kubernetes.io/component=webhook -A --timeout=300s
./deploy.sh -f backboneservices-helmfile.yaml sync            # converges

kubectl wait --for=condition=ready pod postgresql-lts-0 -n egov --timeout=300s   # before §1.7
# filestore's bucket — the minio chart creates none (missing → NoSuchBucket on the first upload)
kubectl exec -n backbone minio-0 -- sh -c \
  'mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc mb -p local/unified-dev-bucket-s3'
```

Always `sync`, never `apply` (helm-diff is broken on helm v4). Order enforced
via `needs:`: **cluster-configs first** (namespaces, ConfigMaps, all
secrets), then cert-manager → ingress-nginx, postgres (release name
`postgresql-lts` — it *is* the DB hostname), redis, minio (single replica),
and Kafka whose release name **must be `release-name`** so the
`kafka-brokers` DNS resolves. `03-backbone.sh` does all of this, including
the webhook retry and the bucket.

### 1.7 Keycloak database

Keycloak (installed by every shape's helmfile) connects as role `keycloak`
with the password in the `kc-db` secret. **Both** the database and the role
are required — a missing role is the classic Keycloak crash-loop
(`password authentication failed for user "keycloak"`):

```bash
KCPW=$(sops -d ../../environments/azure-k3s-secrets.<domain>.yaml | python3 -c \
  'import sys,yaml; print(yaml.safe_load(sys.stdin)["cluster-configs"]["secrets"]["kc-db"]["password"])')
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -c "CREATE DATABASE new_keycloak"
kubectl exec -i -n egov postgresql-lts-0 -- psql -U postgres -v ON_ERROR_STOP=1 <<SQL
CREATE ROLE keycloak LOGIN PASSWORD '$KCPW';
GRANT ALL PRIVILEGES ON DATABASE new_keycloak TO keycloak;
ALTER DATABASE new_keycloak OWNER TO keycloak;
SQL
```

`03-backbone.sh` does this idempotently on the scripted path.

### 1.8 HashiCorp Vault (PII encryption at rest) — on by default

Services with PII (otp, individual) encrypt fields via Vault's **Transit**
engine — stored as `vault:v1:…` ciphertext with a keyed HMAC blind index for
search, one transit key **per tenant** (auto-created on first encrypt). The
shipped environment has Vault **ON** (`vault-enabled: "true"` on otp and
individual, `VAULT_ENABLED` on the dev-bundle and identity-bundle blocks; the
charts carry the `vault-approle` / `hmac-secret` secretKeyRefs, rendered by
cluster-configs from the sops file). This step is therefore optional **only
if you first set those to `"false"`** — with them on and no Vault deployed,
otp/individual (or the bundle JVM) crash-loop in `VaultAuth`.

The chart is `charts/digit3/vault` (official HashiCorp 0.29.1, de-AWS'd:
no gp2 storageClass, no awskms auto-unseal, no public ingress; release name
and namespace MUST be `vault` — egov-config's `vault-host` and
egov-service-host's `vault` keys point there). One idempotent script deploys,
initializes (1-of-1 Shamir, keys written straight into the sops file),
unseals, enables transit + AppRole (`digit-services` role, `digit-transit`
policy covering encrypt/decrypt/sign/verify/keys + token renew-self) and
renders the `vault-approle` secret:

```bash
scripts/04-vault.sh        # reads scripts/.env (written in §1.3): SSH_KEY, DOMAIN, KUBECONFIG_PATH
```

It writes the unseal key, root token and AppRole ids into the secrets file
selected by `DOMAIN` — another reason to use a per-environment file (§1.4)
rather than the tracked shared one.

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

> **Using the published images?** Skip §3.1–3.2 entirely: every bundle and
> `-db` image is on Docker Hub as `egovio/<name>:modulith-<sha>` (same tag as
> the services). Build locally only for your own code.

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

Already present on this branch (nothing to edit for the stock shape):

- `environments/azure-k3s.yaml` — the **`dev-bundle:` block**:
  `pullPolicy: IfNotPresent`; env overrides `TENANT_MIGRATION_ENABLED: "true"`,
  `VAULT_ENABLED: "true"` (set `"false"` only if you skipped §1.8),
  `KEYCLOAK_PUBLIC_BASE_URL`, `URL_SHORTENER_HOST_NAME` (the generated chart
  bakes the harvest-time host), minio-backed S3 (`S3_ACCESS_KEY`/`S3_SECRET_KEY`
  from the `minio` secret, `S3_ENDPOINT: minio.backbone.svc.cluster.local:9000`,
  `S3_USE_SSL: "false"`); `dbMigrationOrder: [combined]` with one
  `dbMigrations.combined` entry (`dev-bundle-db`) whose `DB_URL` points at the
  default `postgres` database.
- `environments/azure-k3s-single-container.yaml` — the overlay:
  `global.domain` and the **`egov-service-host`** keys of the 13 merged
  services → `http://dev-bundle.egov.svc.cluster.local:8080/`.

Image tags are in neither file — both images are
`egovio/dev-bundle{,-db}:$DIGIT_TAG` (§1.5). Switching shape = syncing the
other shape's helmfile (§6.1).

### 3.4 Deploy

```bash
cd deploy-as-code/helm/charts/digit3
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync  # service-host update
DIGIT_TAG=modulith-<sha> ./deploy.sh -f single-container-helmfile.yaml sync   # keycloak, dev-bundle, kong
# sync returns before the pods are up — wait (the init container migrates the public schema first, ~1–3 min)
kubectl rollout status deploy/dev-bundle -n egov --timeout=900s
kubectl rollout status deploy/kong-kong -n egov --timeout=600s
```

### 3.5 Program kong (bundle upstream)

```bash
# kong must be Running first (the §3.4 rollout wait) — setup.py retries transient errors for ~10 s only
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd digit3/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> python3 setup.py
# check: every bundled service's upstream host is the bundle
curl -s http://localhost:18001/services | python3 -c \
  'import sys,json; [print(s["name"], "->", s["host"]) for s in json.load(sys.stdin)["data"]]'
```

(The small Admin-API calls are fine over the tunnelled port-forward; the §1.3
caveat is about bulk data transfer.) By default `setup.py` reads the repo's
`dev-bundle.package.yaml` and repoints every bundled service's kong upstream at
its bundle's Service (`http://<bundle>.<ns>:<port>`, overridable per bundle
with `KONG_BUNDLE_UPSTREAM_<NAME>`); keycloak keeps its own. Set
`KONG_BUNDLE_MANIFESTS=none` for per-service upstreams (§4.2), or point it at
another manifest (`src/bundles/domain-split.package.yaml` yields four bundle
upstreams, §5). Routes/plugins are unchanged (strip_path=false + each
service's context path inside the bundle). The full `setup.py` parameter
reference — every `KONG_*` variable, defaults, per-shape examples — is
`digit3/src/services/kong/README.md`.

### 3.6 Tenant + verify

```bash
# Onboard a tenant through the account API (unprotected bootstrap route; in-cluster,
# so curl from the VM). One call creates the tenant, its Keycloak realm (wait for
# keycloak first) and publishes the migration event every service turns into the
# tenant's schema. Choose the password — a server-generated one is never delivered.
kubectl wait --for=condition=Available deploy/keycloak -n keycloak --timeout=300s
BIP=$(kubectl get svc dev-bundle -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> "curl -s -X POST http://$BIP:8080/account/v3/tenants \
  -H 'Content-Type: application/json' -H 'X-User-ID: bootstrap' \
  -d '{\"name\":\"My Tenant\",\"email\":\"admin@example.org\",\"phone\":\"+919999999999\",\"password\":\"<choose>\"}'"
# → {"code":"MYTENANT", …}   (codes are UPPERCASE, derived from the name)

# The tenant is usable only once ALL 15 tenant-migrating services have consumed the
# event — schema existence is not completion. Wait for 15 Flyway history tables:
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -tAc \
  "SELECT count(*) FROM pg_tables WHERE schemaname='MYTENANT' AND tablename LIKE '%_schema'"   # 15

# schema-only alternative (no tenant record, no realm; endpoint deliberately NOT routed through kong):
ssh -i <key> azureuser@<domain> \
  "curl -s -w '%{http_code}' -X POST http://$BIP:8080/internal/migrate -H 'X-Tenant-ID: DEMO'"   # 200

KIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> \
  "curl -s -o /dev/null -w '%{http_code}' -H 'Host: <domain>' http://$KIP:8000/idgen/"
# every bundled prefix → 401 (JWT), /keycloak → 303
kubectl top pod -n egov -l app=dev-bundle    # ~430Mi for all 16 services
```

`07-seed.sh "<name>" <email> --verify` does the onboarding plus the runtime
lookups every environment needs (otp configs, idgen templates, the OTP SMS
template) and proves the Vault PII pipeline end to end; `08-token.sh` mints a
gateway token for the tenant admin (§7).

---

## 4. `per-service` — each service its own pod

One release per service (idgen, billing, …, 16 in all) plus keycloak and
gateway-kong, from its own helmfile — `per-service-helmfile.yaml` — which
layers `environments/azure-k3s-per-service.yaml` (domain + the 13 per-service
`egov-service-host` keys) and takes its image tags from `DIGIT_TAG`, like the
other shapes. Every service entry is the same pattern:

```yaml
  - name: idgen
    chart: ./idgen
    namespace: egov
    installed: true
    missingFileHandler: Warn
    needs:
      - keycloak/keycloak
    values:
      - ../../environments/azure-k3s-secrets.dec.yaml
      - ../../environments/azure-k3s.yaml
      - ../../environments/azure-k3s-per-service.yaml
      - ./idgen/values.yaml
```

### 4.1 Deploy

```bash
cd deploy-as-code/helm/charts/digit3
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync  # if service-host changed
DIGIT_TAG=modulith-<sha> ./deploy.sh -f per-service-helmfile.yaml sync
# sync returns before the pods are up — each service's init container migrates first (~2–4 min)
kubectl wait --for=condition=Available deploy --all -n egov --timeout=1200s
kubectl get pods -n egov     # 16 service pods + kong, all 1/1 Running (keycloak is in its own namespace)
```

Notes baked into the helmfile: keycloak first; `account` has
`needs: [keycloak/keycloak]`; chart paths are explicit
(`chart: ./idgen`) because helmfile v1 only templates `*.gotmpl` files.

### 4.2 Program kong (per-service upstreams)

Same script **with `KONG_BUNDLE_MANIFESTS=none`** — without it `setup.py`
defaults to the dev-bundle manifest and points every upstream at a
`dev-bundle` Service that does not exist in this shape (every route then 503s
behind a valid token). With `none`, upstreams are the per-service k8s Services
(`http://idgen.egov.svc.cluster.local:8080`, …):

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd digit3/src/services/kong
KONG_BUNDLE_MANIFESTS=none KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> python3 setup.py
curl -s http://localhost:18001/services | python3 -c \
  'import sys,json; [print(s["name"], "->", s["host"]) for s in json.load(sys.stdin)["data"]]'   # <svc>.egov.svc…
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

Then onboard a tenant exactly as in §3.6, with `svc/account` in place of
`svc/dev-bundle`.

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

### 5.1 Deploy

```bash
cd deploy-as-code/helm/charts/digit3
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync   # service-host map → the four bundles
DIGIT_TAG=<tag> ./deploy.sh -f domain-bundles-helmfile.yaml sync              # keycloak, 4 bundles, kong
# sync returns before the pods are up — each bundle's init container migrates its services first
for b in identity-bundle notification-bundle billing-bundle admin-bundle; do
  kubectl rollout status deploy/$b -n egov --timeout=900s
done
kubectl rollout status deploy/kong-kong -n egov --timeout=600s
# equivalently: ./scripts/06-deploy.sh <digit3> domain-bundles <tag>   (does all of the above + §5.2)
```

### 5.2 Program kong (four bundle upstreams)

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd digit3/src/services/kong
KONG_BUNDLE_MANIFESTS=<digit3>/src/bundles/domain-split.package.yaml \
  KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> python3 setup.py
# check: 16 services spread over exactly four hosts (admin 6, identity 4, billing 3, notification 3)
curl -s http://localhost:18001/services | python3 -c \
  'import sys,json,collections; c=collections.Counter(s["host"] for s in json.load(sys.stdin)["data"]); [print(n, h) for h,n in c.items()]'
```

### 5.3 Tenant + verify

As §3.6, with two differences: `account` lives in **identity-bundle**, so the
tenant call goes to `svc/identity-bundle`; and completion means all **four**
bundles consumed the event (each migrates only its own services):

```bash
kubectl wait --for=condition=Available deploy/keycloak -n keycloak --timeout=300s
BIP=$(kubectl get svc identity-bundle -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> "curl -s -X POST http://$BIP:8080/account/v3/tenants \
  -H 'Content-Type: application/json' -H 'X-User-ID: bootstrap' \
  -d '{\"name\":\"My Tenant\",\"email\":\"admin@example.org\",\"phone\":\"+919999999999\",\"password\":\"<choose>\"}'"
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -tAc \
  "SELECT count(*) FROM pg_tables WHERE schemaname='MYTENANT' AND tablename LIKE '%_schema'"   # 15
kubectl exec -n backbone release-name-kafka-controller-0 -- \
  /opt/bitnami/kafka/bin/kafka-consumer-groups.sh --bootstrap-server localhost:9092 --list | grep bundle   # 4 groups
KIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> \
  "curl -s -o /dev/null -w '%{http_code}' -H 'Host: <domain>' http://$KIP:8000/idgen/"   # 401; /keycloak → 303
kubectl top pods -n egov | grep bundle     # ~1.3 GB across the four JVMs
```

`07-seed.sh "<name>" <email> --verify` and `08-token.sh` work unchanged on this
shape.

---

## 6. Custom combinations, peeling, re-absorbing, switching

> For a step-by-step custom-grouping walkthrough (what changes vs the stock
> shapes, with commands), see [CUSTOM-BUNDLING.md](CUSTOM-BUNDLING.md). This
> section is the reference behind it.

The three stock configurations are just points on a spectrum — the manifest
accepts any partition of the catalog:

- **Regroup** (move a service between bundles): edit the `include:` lists,
  regenerate, rebuild the affected bundles' images + charts, sync, rerun
  `setup.py`. The generator refuses nothing except a service in two bundles.
- **Peel one service out to run standalone** (executed for billing; full war
  story on branch `modulith-separate-billing`): remove its name from
  `include:`; if co-bundled callers reached it over loopback, re-declare those
  hosts env-overridable in `overrides:`; regenerate; update the bundle's
  hand-written tests to *pin the absence*. Then on the deploy side:
  - build the standalone service's app **and** db image from the same source
    tree — an externally-pinned db image fails Flyway checksum validation
    against the history the bundle already applied;
  - chart values: datasource + init `DB_URL` → the same default **`postgres`**
    database the bundle uses (its data lives there), and
    **`TENANT_MIGRATION_ENABLED: "true"`** (standalone it must consume tenant
    events itself);
  - re-add its helmfile release, and set its `egov-service-host` key back to
    per-service DNS in the shape overlay (`azure-k3s-<shape>.yaml`);
  - **sync the bundle BEFORE the standalone service** (the ingress admission
    webhook rejects a duplicate path while the old bundle Ingress still owns
    it; helmfile syncs concurrently — use `-l` selectors), and rollout-restart
    consumers of changed `egov-service-host` keys (configMapKeyRef env resolves
    at pod start);
  - rerun `setup.py` — the service is in no bundle now, so its upstream reverts
    to per-service DNS automatically.
- **Re-absorb**: the exact mirror — add the name back to `include:`,
  regenerate, uninstall the standalone release, sync the bundle, rerun `setup.py`.

### 6.1 Switching whole shapes

Shapes are mutually exclusive (same ingress paths, same kong prefixes), so
uninstall the old shape's releases first, then deploy the new shape and rerun
`setup.py`. Data note: every shape uses the same default `postgres` database
(tenants separate by schema), so the data is simply still there after a
switch — nothing is migrated or copied.

**per-service → single-container** — remove the services first:

```bash
for r in account apportion billing boundary employee filestore \
         idgen individual localization notification otp pg-service \
         registry template-config url-shortener workflow; do
  helm uninstall "$r" -n egov
done
DIGIT_TAG=<tag> ./deploy.sh -f single-container-helmfile.yaml sync   # then §3.5 kong repoint
```

**single-container → per-service**:

```bash
helm uninstall dev-bundle -n egov
DIGIT_TAG=<tag> ./deploy.sh -f per-service-helmfile.yaml sync        # then §4.2 setup.py
```

Finally (either shape): open NSG 80/443 → the `cm-acme-http-solver` pods
complete, certificates issue, and `https://<domain>/<service>` works publicly.

---

## 7. Calling the APIs through Kong

Anonymous requests get **401** from the gateway; `/keycloak` redirects (303).
An authenticated call needs a token that satisfies the `keycloak-rbac` plugin,
which authorizes every request with a UMA check against Keycloak's
**in-cluster** URL. Three requirements (each produces a distinct error when
missed):

1. **Issuer must be the cluster-DNS URL** the plugin itself uses
   (`http://keycloak.keycloak.svc.cluster.local:8080/keycloak`). A token minted
   via the public URL or a ClusterIP fails the UMA check with
   `401 "Token rejected by Keycloak"`.
2. **Client must be `auth-server`** (confidential; its per-realm secret is
   readable via the Keycloak admin API). `admin-cli` tokens carry no realm
   roles → the service answers `403 "No roles found in token"`.
3. **The user needs realm roles** — tenant admins created by the account
   service get `SUPERUSER`/`ADMIN`, which pass the UMA decision.

`scripts/08-token.sh <TENANT-CODE> <email> [password]` does all of this and
prints a ready bearer token plus a sample curl:

```bash
./scripts/08-token.sh MYTENANT admin@example.org      # password prompted silently
curl -H "Authorization: Bearer <token>" -H "X-Tenant-ID: MYTENANT" \
     -H "Host: <domain>" http://<kong-proxy-ip>:8000/individual/v3/individuals
```

Kong's header-enrichment injects the user identity from the JWT (audit fields
show the Keycloak user id), so `X-User-ID` is not needed on gateway calls —
only on direct in-cluster calls that bypass Kong. The `/…/internal/migrate`
endpoints are deliberately never routed through Kong (ops-plane; reachable only
in-cluster).

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
| Bundle / otp / individual crash-loop in `VaultAuth`; PII calls 500 after a Vault pod restart | Vault is on by default — run §1.8 (`04-vault.sh`; rerun after any Vault restart to unseal), or set `vault-enabled` / `VAULT_ENABLED` to `"false"` |
| Rendered Ingress "apiVersion not set" | generator template `{{- if … -}}` swallowed the line — fixed in `generate_bundle_chart.py` |
| 400 `MISSING_HEADER` on every request | DIGIT 3.x requires `X-Tenant-ID` (+ `X-User-ID` for writes); kong injects them from the JWT in production |
| Tenant code rejected with 400 ValidationFailed | account service requires UPPERCASE tenant codes |
| `kubectl port-forward` hangs/000 over the SSH tunnel | curl ClusterIPs from the VM over SSH instead |
| `bind :16443: Address already in use` on tunnel setup | old tunnel still bound; test kubectl first, else `pkill -f "16443:127.0.0.1:6443"` and reconnect |
| Ingress webhook: "path /X is already defined in ingress egov/dev-bundle" | both shapes publish the same path; sync dev-bundle BEFORE the peeled service (helmfile syncs concurrently — use `-l` selectors) |
| Peeled service init: "Migration checksum mismatch" | externally-built db image ≠ the copies the bundle applied; build the service's db image from the same source tree |
| Pod calls old upstream after `egov-service-host` change | `configMapKeyRef` env resolves at pod start → rollout-restart consumers after cluster-configs sync |
| Every service init container: `FATAL: password authentication failed for user "postgres" (28P01)` | `db.password` ≠ `db.flywayPassword` in the secrets file — same postgres user, must be identical (§1.4) |
| Keycloak crash-loops: `password authentication failed for user "keycloak"` | §1.7 created the database but not the `keycloak` role — create role + grant + owner |
| Per-service: valid token but every route 503; kong upstreams show `dev-bundle.egov…` | `setup.py` run without `KONG_BUNDLE_MANIFESTS=none` (§4.2) — rerun with it |
| `setup.py`: connection refused / 5xx right after the shape sync | kong not Running yet — `kubectl rollout status deploy/kong-kong -n egov`, then rerun (built-in retries cover ~10 s only) |
| kong pods `Init:CrashLoopBackOff`; init log "Database has pending migrations; run 'kong migrations finish'" | two first-boot replicas raced the unserialized init migration — chart ships `autoscaling.minReplicas: 1` for this; recover with a one-off pod running `kong migrations up -y && kong migrations finish`, then delete the kong pods |
| filestore upload: `NoSuchBucket` | the minio chart creates no bucket — `mc mb -p local/unified-dev-bucket-s3` (§1.6) |
| Pods `ImagePullBackOff`; events `429 Too Many Requests … unauthenticated pull rate limit` | Docker Hub anonymous cap (e.g. parallel installs from one egress IP) — wait for the window, or configure `docker-registry-secret` with Hub credentials |
