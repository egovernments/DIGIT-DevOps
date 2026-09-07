# DIGIT 3 on single-node k3s — full replication guide

Two ways to run DIGIT 3 on one k3s node, exactly as deployed on
`modulith.digit.org` (Azure VM, 8 vCPU / 32 GB / 100 GB, Ubuntu 22.04):

- **Option A — Modulith bundle**: the 16 core services compiled into ONE
  Spring Boot JVM (`dev-bundle`, ~430 Mi). One app pod, one db-migration
  init image. See [BUNDLING.md](./BUNDLING.md) for how it works internally.
- **Option B — Per-service (microservice shape)**: every service as its own
  helm release / pod (~16 JVMs, ~5 GB).

Both options sit on the **same foundation** (Section 1): k3s, secrets,
backbone infra, keycloak, kong. **Deploy exactly one option at a time** —
they publish the same ingress context paths and kong prefixes, so running
both clashes. Switching between them is covered in Section 4.

Repos used (both on the `modulith` branch):

| Repo | Role |
|---|---|
| `DIGIT-DevOps` | helm charts (`charts/digit3`, `charts/bundles/dev-bundle`), environments, bundler chart generator |
| `digit3` | service source, bundle generator (`src/bundles/`), kong bootstrap (`src/services/kong/setup.py`) |

Workstation prerequisites: `kubectl`, `helm` (v4 tested), `helmfile` (v1.7+),
`sops` + `age`, `docker` (with buildx), JDK 25 (Temurin), Maven 3.9+,
`python3` with `pyyaml` and `requests`.

---

## 1. Common foundation (required for BOTH options)

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

(Keycloak itself is installed by the services helmfile in both options.)

---

## 2. Option A — Deploy the modulith bundle

The `modulith` branch helmfile is already in this shape:
`digit3services-helmfile.yaml` contains keycloak, **dev-bundle**,
accesscontrol-java (not part of the bundle) and gateway-kong.

### 2.1 Build the bundle jar (workstation)

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

### 2.2 Build linux/amd64 images and load them into k3s (no registry)

```bash
mkdir /tmp/bundle-image && cp src/bundles/dev-bundle/target/dev-bundle-*.jar /tmp/bundle-image/app.jar
cat > /tmp/bundle-image/Dockerfile <<'EOF'
FROM amazoncorretto:25
WORKDIR /opt/egov
COPY app.jar /opt/egov/app.jar
EXPOSE 8085
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

### 2.3 Bundle chart + database + environment

```bash
# regenerate the bundle chart if the manifest changed (committed output: charts/bundles/dev-bundle)
cd DIGIT-DevOps/deploy-as-code/helm/bundler
python3 generate_bundle_chart.py --manifest <digit3>/src/bundles/dev-bundle.package.yaml

# the bundle owns its own database
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -c "CREATE DATABASE bundle_db"
```

`environments/azure-k3s.yaml` needs (already present on this branch — update
the two `tag:` values to your `$TAG`):

- a **`dev-bundle:` block**: image `dev-bundle:<TAG>` +
  `pullPolicy: IfNotPresent`; env overrides `DB_NAME: bundle_db`
  (egov-config's db-name is the per-service DB),
  `TENANT_MIGRATION_ENABLED: "true"`, `VAULT_ENABLED: "false"` (no Vault
  here — otp's client crash-loops the JVM otherwise),
  `KEYCLOAK_PUBLIC_BASE_URL`, and minio-backed S3
  (`S3_ACCESS_KEY`/`S3_SECRET_KEY` from the `minio` secret,
  `S3_ENDPOINT: minio.backbone.svc.cluster.local:9000`,
  `S3_USE_SSL: "false"`); `dbMigrationOrder: [combined]` with one
  `dbMigrations.combined` entry using `dev-bundle-db:<TAG>` and `DB_URL`
  pointing at `bundle_db`.
- **`egov-service-host`** keys of the 13 merged services →
  `http://dev-bundle.egov.svc.cluster.local:8085/`.

### 2.4 Deploy

```bash
cd deploy-as-code/helm/charts/digit3
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync  # service-host update
./deploy.sh -f digit3services-helmfile.yaml sync                            # keycloak, dev-bundle, accesscontrol, kong
kubectl get pods -n egov -l app=dev-bundle   # init container migrates public schema, then 1/1 Running
```

### 2.5 Program kong (bundle upstream)

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd digit3/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> \
  KONG_BUNDLE_UPSTREAM=http://dev-bundle.egov.svc.cluster.local:8085 python3 setup.py
```

`KONG_BUNDLE_UPSTREAM` repoints every bundled service's kong upstream at the
single bundle Service; keycloak keeps its own. Routes/plugins are unchanged
(strip_path=false + each service's context path inside the bundle).

### 2.6 Tenant + verify

```bash
# tenant migration (endpoint deliberately NOT routed through kong; run in-cluster)
BIP=$(kubectl get svc dev-bundle -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> \
  "curl -s -w '%{http_code}' -X POST http://$BIP:8085/internal/migrate -H 'X-Tenant-ID: DEMO'"
# tenant codes are validated UPPERCASE by the account service

KIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> \
  "curl -s -o /dev/null -w '%{http_code}' -H 'Host: <domain>' http://$KIP:8000/idgen/"
# every bundled prefix → 401 (JWT), /keycloak → 303
kubectl top pod -n egov -l app=dev-bundle    # ~430Mi for all 16 services
```

---

## 3. Option B — Deploy each service separately (microservice shape)

This is the pre-bundle shape of `digit3services-helmfile.yaml`: one release
per service (idgen-java, billing-java, …, 16 in all) plus keycloak,
accesscontrol-java and gateway-kong. On the `modulith` branch those 16
entries were replaced by `dev-bundle` — to deploy per-service, check out the
helmfile from the commit before the bundle cutover (or re-add the release
entries; each is the same 8-line pattern):

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

The per-service env blocks (image tags, init-container tags) are **still
present** in `azure-k3s.yaml` — they were kept for exactly this purpose.
Also revert the 13 `egov-service-host` keys from
`dev-bundle.egov…:8085` back to the per-service hosts
(`http://idgen-java:8080/`, …).

### 3.1 Deploy

```bash
cd deploy-as-code/helm/charts/digit3
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync  # if service-host changed
./deploy.sh -f digit3services-helmfile.yaml sync
kubectl get pods -n egov     # expect ~16 service pods + keycloak + kong, all Running
```

Notes baked into the helmfile: keycloak first; `account-java` has
`needs: [keycloak/keycloak]`; chart paths are explicit
(`chart: ./idgen-java`) because helmfile v1 only templates `*.gotmpl` files.

### 3.2 Program kong (per-service upstreams)

Same script, just **without** `KONG_BUNDLE_UPSTREAM` — upstreams then point
at the per-service k8s Services (`http://idgen-java.egov.svc.cluster.local:8080`, …):

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd digit3/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> python3 setup.py
```

### 3.3 Verify

```bash
kubectl get pods -A          # everything Running
KIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
ssh -i <key> azureuser@<domain> \
  "curl -s -o /dev/null -w '%{http_code}' -H 'Host: <domain>' http://$KIP:8000/idgen/"  # 401
ssh -i <key> azureuser@<domain> \
  "curl -s -o /dev/null -w '%{http_code}' -H 'Host: <domain>' http://$KIP:8000/keycloak" # 303
```

---

## 4. Switching between the two shapes

The shapes are mutually exclusive (same ingress paths, same kong prefixes).
Data note: the bundle uses its own `bundle_db`; the per-service shape uses
the `postgres` DB — the two datasets are independent, so switching does not
migrate data.

**B → A (services → bundle)** — the order matters, remove services first:

```bash
for r in account-java apportion billing-java boundary-java employee-java filestore-java \
         idgen-java individual-java localization-java notification-java otp-java pg-service \
         registry-java template-config-java url-shortener-java workflow-java; do
  helm uninstall "$r" -n egov
done
# then follow Option A from 2.3 (env/service-host) → 2.4 sync → 2.5 kong repoint
```

**A → B (bundle → services)**:

```bash
helm uninstall dev-bundle -n egov
# restore the 16 release entries in the helmfile + per-service egov-service-host keys,
# then Option B 3.1 sync → 3.2 setup.py WITHOUT KONG_BUNDLE_UPSTREAM
```

Finally (either shape): open NSG 80/443 → the `cm-acme-http-solver` pods
complete, certificates issue, and `https://<domain>/<service>` works
publicly.

---

## 5. Peeling one service out of the bundle (worked example: billing)

Sometimes one service needs to scale, fail, or release independently while the
rest stay bundled. The design makes the *jar* side trivial ("remove the
manifest entry and regenerate"), but a full deployment peel touches five
layers. This section is the generic procedure; the executed billing peel
lives on branch **`modulith-separate-billing`** in both repos (DIGIT-DevOps
`05e09c83d`, digit3 `52a570c0`) — every referenced change can be read there
verbatim.

### 5.1 digit3: manifest + overrides + tests

- Delete the service's entry from `dev-bundle.package.yaml` `services:`.
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

### 5.2 Images — same source tree for everything (important)

Build and import (§2.2 mechanics) with a new tag: the **bundle pair** AND the
**peeled service's app + db images**, all from the same digit3 checkout:

```bash
# app: runtime-only image from the service's *-exec.jar
# db:  from src/services/<svc>/src/main/resources/db (its own Dockerfile)
```

Do NOT reuse an externally-pinned per-service db image: the billing peel
failed exactly there — the old image carried a different copy of one
migration, and Flyway rejected it against the history the bundle had already
applied to `bundle_db` ("Migration checksum mismatch"). Same source tree →
identical files → validation passes.

### 5.3 DIGIT-DevOps: chart, values, env, helmfile

- Rerun `generate_bundle_chart.py` — the peeled service's ingress context and
  `dbMigrations` entry disappear, and the *callers'* harvested env pointing
  at it (`APPORTION_BILLING_HOST`, `BILLING_HOST` ← `egov-service-host` key
  `billing-java`) automatically **survives** the merge now (loopback
  detection only drops env for bundled services). No manual env plumbing.
- Peeled service's chart values: point its datasource AND its db-migration
  init `DB_URL` at **`bundle_db`** — its public tables, Flyway history and
  tenant schemas were created there while bundled; `egov-config`'s `db-url`
  is the wrong (per-service) database.
- Peeled service's chart values: set **`TENANT_MIGRATION_ENABLED: "true"`** —
  the per-service charts ship it `false` (inside the bundle the bundle-level
  env owns the switch), and a standalone service with it off silently ignores
  tenant-create events. Found live: creating tenant TEST produced 53/72
  tables, all 19 missing ones billing's; enabling the flag made the consumer
  replay the event at startup and complete the schema.
- `environments/<env>.yaml`: bump the `dev-bundle:` tags; point the peeled
  service's image + init image at the source-built tags
  (`pullPolicy: IfNotPresent` for containerd-imported images); revert its
  `egov-service-host` key from `dev-bundle…:8085` to its own Service.
- Helmfile: re-add the service's release entry (its env block was kept).

### 5.4 Deploy — order matters

```bash
./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync   # service-host key
./deploy.sh -f digit3services-helmfile.yaml -l name=dev-bundle sync          # FIRST: frees /billing
./deploy.sh -f digit3services-helmfile.yaml -l name=billing-java sync        # THEN the peeled service
kubectl rollout restart deploy/dev-bundle -n egov                            # see below
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

### 5.5 Kong

```bash
KONG_ADMIN_URL=… KONG_ROUTE_HOSTS=<domain> \
  KONG_BUNDLE_UPSTREAM=http://dev-bundle.egov.svc.cluster.local:8085 \
  KONG_BUNDLE_EXCLUDE=billing python3 setup.py
```

`KONG_BUNDLE_EXCLUDE` (comma-separated) keeps peeled services on their
per-service upstreams while the rest stay on the bundle. Route paths never
change, so clients notice nothing.

### 5.6 Verify + aftermath

- Bundle: peeled prefix NOT served (expect the 400-coded
  `NoResourceFoundException` envelope — the platform renders 404s that way);
  all other prefixes intact.
- Peeled pod: init container validates cleanly against `bundle_db`; a
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

## 6. Gotchas index (hard-won, all encountered on this install)

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
