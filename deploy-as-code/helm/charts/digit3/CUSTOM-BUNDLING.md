# DIGIT 3 — Custom Bundling

The three out-of-the-box shapes (single-container, domain-bundles, per-service)
are just three points on a spectrum. **Any partition of the 16-service catalog
is valid** — you can group services into whatever set of JVMs suits your
scaling and release boundaries. This page covers a *custom* grouping: what
changes versus the OOB path, and the exact steps.

Reference material for the mechanics (peeling one service out, re-absorbing,
cross-bundle wiring) lives in [INSTALL.md §6](INSTALL.md); the generator and
its manifest are documented in `digit3/src/bundles/README.md`; this page is the
practical how-to.

---

## What stays the same, what changes

The install has a **shape-independent foundation** and a **shape-specific
deploy**. Custom bundling only touches the second half.

| Phase | OOB shapes | Custom bundling |
|---|---|---|
| 01 cluster | `01-cluster.sh` | **same** |
| 02 secrets | `02-secrets.sh` | **same** |
| 03 backbone | `03-backbone.sh` | **same** |
| 04 vault | `04-vault.sh` | **same** |
| 05 images | published, preflighted by `install.sh` | **you build** — locally, or by registering the bundle in the Actions pipeline (§2) |
| 06 deploy | `--shape` picks a fixed helmfile + manifest | **you drive the generators + a hand-written overlay and helmfile** (§3–§7) |
| 07 seed | `07-seed.sh` resolves endpoints by shape | **same script**, told which Service owns each endpoint (§8) |

`install.sh --shape` / `06-deploy.sh <digit3> <shape>` map to *fixed* bundle
names, helmfiles and manifests, so they **do not** cover a custom grouping. Run
phases 01–04 with the scripts as usual, then follow the steps below in place
of 05–06.

---

## 1. Define your grouping in a manifest

Copy an existing manifest in the digit3 repo (`src/bundles/`) — start from
`domain-split.package.yaml` (multi-bundle) — and edit the `bundles:` list. The
`services:` catalog above it stays as is. **Name the file after your shape**
(`<yourshape>.package.yaml`) — the overlay in §5 and the chart generator's
drift check key off that name. Each bundle entry is one JVM:

```yaml
bundles:
  - name: core-bundle              # becomes the k8s release + Service name
    groupId: org.digit.bundles
    artifactId: core-bundle
    version: 1.0.0-SNAPSHOT
    bootVersion: 4.0.7
    javaVersion: 25
    mainPackage: org.digit.bundles.core
    mainClass: CoreBundleApplication
    port: 8080                     # namespace-scoped; keep 8080
    outputDir: core-bundle
    include:                       # the services in THIS JVM (order = tenant-migration order)
      - idgen
      - individual
      - account
      - otp
    overrides:
      # datasource (copy from any existing bundle — the default database is `postgres`)
      spring.datasource.url: "jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME:postgres}?sslmode=${DB_SSL_MODE:disable}"
      # ...and one entry per CROSS-BUNDLE call, parameterized so it defaults to
      # the callee bundle's cluster-DNS name (see the domain-split manifest for
      # the pattern: ${OTHER_BUNDLE_HOST:http://other-bundle.egov.svc.cluster.local:8080})
  # ...more bundles
```

Rules the generator enforces / you must respect:
- **A service is in at most one bundle** — the generator exits if two bundles
  include the same service. A service in **no** bundle is allowed: it runs
  standalone from its per-service chart (the generator says so in its report;
  see INSTALL.md §6 for the standalone/peel mechanics).
- **Intra-bundle calls** stay on loopback (`http://localhost:${SERVER_PORT}`);
  **cross-bundle calls** must be env-parameterized in `overrides:` so they
  resolve to the callee's Service by default. Copy the `*_BUNDLE_HOST` pattern
  from `domain-split.package.yaml`.
- Keep `boundary` last in whichever bundle's `include:` holds it (its PostGIS
  migration fail-fasts on a Postgres without the extension).

Generate, and check the report:

```bash
cd <digit3>
python3 src/bundles/generate_bundle.py src/bundles/<yourshape>.package.yaml
# must print "no unresolved property conflicts"; a "catalog services in NO bundle"
# note lists what will run standalone. Run it twice: the second run changes nothing.
```

## 2. Build the images (required)

No published image exists for a custom bundle. Each bundle needs its app image
**and** its db-migration image, built **from the same digit3 tree** (a db image
from another tree fails Flyway checksum validation). Two ways:

**Publish through the Actions pipeline** (the way the stock bundles are built —
`digit3/src/bundles/README.md` §5): register the pair in `build/build-config.yml`
(one entry per bundle: the app image from `src/bundles/<bundle>`, the `-db`
image from `src/bundles/<bundle>/src/main/resources/db`) and add the bundle
name to the `service` dropdown in `.github/workflows/build.yaml`; push; run
the workflow for each bundle. The images appear on Docker Hub as
`egovio/<bundle>:modulith-<sha>` and `egovio/<bundle>-db:modulith-<sha>`, and
the VM pulls them like any other.

**Or build locally** and load straight into the node's containerd (single-node
k3s; the env block sets `pullPolicy: IfNotPresent`):

```bash
TAG=custom-$(git -C <digit3> rev-parse --short HEAD)
for B in core-bundle other-bundle; do        # your bundle names
  docker buildx build --platform linux/amd64 --load -t egovio/$B:$TAG \
    -f <digit3>/src/bundles/$B/Dockerfile <digit3>          # build context = repo root
  docker buildx build --platform linux/amd64 --load -t egovio/$B-db:$TAG \
    <digit3>/src/bundles/$B/src/main/resources/db
  docker save egovio/$B:$TAG    | ssh -i <key> azureuser@<domain> 'sudo k3s ctr images import -'
  docker save egovio/$B-db:$TAG | ssh -i <key> azureuser@<domain> 'sudo k3s ctr images import -'
done
```

## 3. Generate the charts

One run regenerates **every** bundle in the manifest (no per-bundle flag):

```bash
cd DIGIT-DevOps/deploy-as-code/helm
python3 bundler/generate_bundle_chart.py --manifest <digit3>/src/bundles/<yourshape>.package.yaml
# → charts/bundles/<each bundle in the manifest>; read the generation report
```

## 4. Add an env block per bundle

In `environments/azure-k3s.yaml`, add one block per custom bundle, modelled on
the existing `identity-bundle:` / `admin-bundle:` blocks:

- `image.repository: <bundle>` + `pullPolicy: IfNotPresent`, and the same for
  the `dbMigrations.combined` image (`<bundle>-db`).
- **Tags.** Stock bundles get their tag from `environments/digit-tag.yaml.gotmpl`
  (`DIGIT_TAG`); a custom bundle name is not in that file, so either **add your
  bundles to `digit-tag.yaml.gotmpl`** (recommended — one tag source, and
  `DIGIT_TAG=<tag>` then pins them too) or set `image.tag` and the
  `dbMigrations.combined` tag explicitly in the block.
- `dbMigrations.combined` `DB_URL: jdbc:postgresql://postgresql-lts.egov:5432/postgres`
  — every shape uses the cluster's default `postgres` database; tenants separate
  by schema. No database to create.
- `TENANT_MIGRATION_ENABLED: "true"` (each bundle consumes tenant events for
  its own services).
- **On the bundle that includes `filestore`**: the minio S3 overrides
  (`S3_ACCESS_KEY`/`S3_SECRET_KEY` from the `minio` secret, `S3_ENDPOINT`,
  `S3_USE_SSL: "false"`).
- **On the bundle that includes `individual`/`otp`**: `VAULT_ENABLED: "true"`
  (the role/secret/HMAC refs are chart defaults; needs §1.8 Vault).

## 5. Write a shape overlay

The stock shapes each have an overlay (`environments/azure-k3s-<shape>.yaml`)
that sets the domain, the 13 merged services' `egov-service-host` keys, and
each bundle's `KEYCLOAK_PUBLIC_BASE_URL`. Copy
`environments/azure-k3s-domain-bundles.yaml` to
**`environments/azure-k3s-<yourshape>.yaml`** (same stem as the manifest) and:

- set `global.domain`;
- for every merged service, set its `egov-service-host` key to
  `http://<the-bundle-that-includes-it>.egov.svc.cluster.local:8080/`;
- give each bundle block `KEYCLOAK_PUBLIC_BASE_URL: https://<domain>/keycloak`.

Because the overlay carries the manifest's stem, the chart generator's drift
check compares it against the composition on every run and warns if a key
points at the wrong bundle — name it anything else and the check silently
skips. The map reaches the cluster through the `cluster-configs` release your
helmfile lists first (§6) — the backbone helmfile syncs that release with base
values only, so there is no separate re-sync step: the §6 sync applies it.

## 6. Write a helmfile for your bundles

Copy `domain-bundles-helmfile.yaml` to `<yourshape>-helmfile.yaml`, point
its `cluster-configs` and `keycloak` releases at **your** overlay, and list
**your** bundle releases (each `chart: ../bundles/<name>`) plus `gateway-kong`.
Keep `cluster-configs` first with `keycloak` needing it (it carries your
overlay's `egov-service-host` map), and give **every** bundle
`needs: [keycloak/keycloak]` — helmfile syncs concurrently, and the bundles need
Keycloak's realm endpoints. Keep each bundle's `values:` in the stock order —
`azure-k3s-secrets.dec.yaml`, `azure-k3s.yaml`, your overlay,
`digit-tag.yaml.gotmpl` — that is where `DIGIT_TAG` is applied. Then sync:

```bash
DIGIT_TAG=<tag> ./deploy.sh -f <yourshape>-helmfile.yaml sync
for b in core-bundle other-bundle; do kubectl rollout status deploy/$b -n egov --timeout=900s; done
kubectl rollout status deploy/kong-kong -n egov --timeout=600s
```

`DIGIT_TAG` is mandatory (`requiredEnv` fails the deploy without it) even if
you set explicit tags in §4 — it also pins any stock images the helmfile lists.

## 7. Program Kong from your manifest

Kong derives upstreams straight from the manifest — no per-bundle config. Kong
must be Running first (the rollout wait above; nothing else waits for it on
this path):

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd <digit3>/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> \
  KONG_BUNDLE_MANIFESTS=<digit3>/src/bundles/<yourshape>.package.yaml python3 setup.py
curl -s http://localhost:18001/services | python3 -c \
  'import sys,json,collections; c=collections.Counter(s["host"] for s in json.load(sys.stdin)["data"]); [print(n, h) for h,n in c.items()]'
```

Routes and plugins are the same for every shape; only each service's upstream
host changes. A service in no bundle keeps its per-service upstream. Every `KONG_*`
parameter, with defaults and per-shape examples: `digit3/src/services/kong/README.md`.

## 8. Seed + verify

`07-seed.sh` resolves endpoints by shape for the stock shapes; for a custom
grouping tell it which **Service** owns each endpoint (unset ones default to
`ACCOUNT_SVC`), and it does everything it does for the stock shapes — tenant +
realm, the 15/15 fan-out wait, otp configs, idgen templates, the OTP SMS
template, the one-time admin password, and with `--verify` the Vault PII proof:

```bash
cd charts/digit3/scripts
ACCOUNT_SVC=core-bundle IDGEN_SVC=core-bundle INDIVIDUAL_SVC=core-bundle \
  NOTIFICATION_SVC=other-bundle OTP_SVC=core-bundle \
  ./07-seed.sh "My Tenant" admin@example.org --verify
./08-token.sh MYTENANT admin@example.org      # then call through kong (INSTALL.md §7)
```

---

## Changing a grouping later

- **Regroup** (move a service between bundles): edit the `include:` lists,
  redo steps 1–7 for the affected bundles (regenerate, rebuild both images,
  regenerate charts, update the overlay's keys, sync, rerun `setup.py`).
- **Peel a service out to standalone** or **re-absorb** it: the detailed,
  order-sensitive procedure (build both images from one tree, flip
  `TENANT_MIGRATION_ENABLED`, sync-order vs the ingress webhook, rollout-restart
  consumers) is in **[INSTALL.md §6](INSTALL.md)** — follow it verbatim.

Data note: every shape — stock or custom — uses the same default `postgres`
database, with tenants separated by schema. Switching groupings does not
migrate or copy data; it is simply still there.
