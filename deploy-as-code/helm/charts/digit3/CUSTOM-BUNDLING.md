# DIGIT 3 — Custom Bundling

The three out-of-the-box shapes (single-container, domain-bundles, per-service)
are just three points on a spectrum. **Any partition of the 16-service catalog
is valid** — you can group services into whatever set of JVMs suits your
scaling and release boundaries. This page covers a *custom* grouping: what
changes versus the OOB path, and the exact steps.

Reference material for the mechanics (peeling one service out, re-absorbing,
cross-bundle wiring) lives in [INSTALL.md §7](INSTALL.md); this page is the
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
| 05 images | published pins, no build | **you build** (no published image exists for a custom grouping) |
| 06 deploy | `--shape` picks a fixed helmfile + manifest | **you drive the generator + a hand-written helmfile** |
| 07 seed | `07-seed.sh` resolves endpoints by shape | **point it at the bundle that owns account/idgen/individual** |

The `install.sh --shape` / `06-deploy.sh <digit3> <shape>` path maps to *fixed*
bundle names, helmfiles, and manifests, so it **does not** cover a custom
grouping. Run phases 01–04 with the scripts as usual, then follow the steps
below in place of 05–06.

---

## 1. Define your grouping in a manifest

Copy an existing manifest in the digit3 repo (`src/bundles/`) — start from
`domain-split.package.yaml` (multi-bundle) — and edit the `bundles:` list.
Each bundle entry is one JVM:

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
      # datasource (copy from any existing bundle)
      spring.datasource.url: "jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME:bundle_db}?sslmode=${DB_SSL_MODE:disable}"
      # ...and one entry per CROSS-BUNDLE call, parameterized so it defaults to
      # the callee bundle's cluster-DNS name (see the domain-split manifest for
      # the pattern: ${OTHER_BUNDLE_HOST:http://other-bundle.egov.svc.cluster.local:8080})
  # ...more bundles; every one of the 16 services must appear in exactly one
```

Rules the generator enforces / you must respect:
- **Every service in exactly one bundle** (the generator refuses a service in
  two; a service in none becomes standalone — see INSTALL.md §7 for peeling).
- **Intra-bundle calls** stay on loopback (`http://localhost:${SERVER_PORT}`);
  **cross-bundle calls** must be env-parameterized in `overrides:` so they
  resolve to the callee's Service by default. Copy the `*_BUNDLE_HOST` pattern
  from `domain-split.package.yaml`.
- Keep `boundary` last in whichever bundle's `include:` holds it (migration
  ordering convention).

Validate the grouping compiles into a jar with no unresolved properties:

```bash
cd <digit3>
python3 src/bundles/generate_bundle.py src/bundles/<your>.package.yaml
# must print "no unresolved property conflicts"
```

## 2. Build and load the images (required)

No published image exists for a custom bundle, so build each bundle's app +
db-migration image **from the same digit3 tree** (mismatched db images fail
Flyway checksum validation) and import into the node's containerd:

```bash
TAG=custom-$(git -C <digit3> rev-parse --short HEAD)
for B in core-bundle other-bundle; do        # your bundle names
  docker buildx build --platform linux/amd64 --load -t egovio/$B:$TAG \
    -f <digit3>/src/bundles/$B/Dockerfile <digit3>
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
python3 bundler/generate_bundle_chart.py --manifest <digit3>/src/bundles/<your>.package.yaml
# → charts/bundles/<each bundle in the manifest>
```

## 4. Add an env block per bundle

In `environments/azure-k3s.yaml`, add one block per custom bundle (model them
on the existing `identity-bundle:` / `admin-bundle:` blocks):

- `image.repository: <bundle>` + `image.tag: $TAG` + `pullPolicy: IfNotPresent`
- the same for `dbMigrations.combined.image` (`<bundle>-db:$TAG`)
- `DB_NAME: bundle_db`, `TENANT_MIGRATION_ENABLED: "true"`,
  `KEYCLOAK_PUBLIC_BASE_URL`
- **on the bundle that includes `filestore`**: the minio S3 overrides
  (`S3_ACCESS_KEY`/`S3_SECRET_KEY` from the `minio` secret, `S3_ENDPOINT`,
  `S3_USE_SSL: "false"`)
- **on the bundle that includes `individual`/`otp`**: `VAULT_ENABLED: "true"`
  (the role/secret/HMAC refs are chart defaults)

## 5. Write a shape overlay with your service-host map

The stock shapes each have an overlay (`environments/azure-k3s-<shape>.yaml`)
that sets the domain and repoints the 16 `egov-service-host` keys at the
owning Service. Copy `environments/azure-k3s-domain-bundles.yaml` to
`environments/azure-k3s-<yourshape>.yaml` and, for every service, set its key
to `http://<the-bundle-that-includes-it>.egov.svc.cluster.local:8080/`. The
chart generator's own drift check will warn on the next run if an overlay key
disagrees with the manifest's composition, so this stays honest. Re-sync
cluster-configs so pods pick it up:

```bash
cd charts/digit3
DIGIT_TAG=<tag> ./deploy.sh -f backboneservices-helmfile.yaml -l name=cluster-configs sync
```

## 6. Write a helmfile for your bundles

Copy `domain-bundles-helmfile.yaml` to
`<yourshape>-helmfile.yaml` and list **your** bundle releases
(each `chart: ../bundles/<name>`) plus `keycloak` and `gateway-kong`. Give the
first bundle `needs: [keycloak/keycloak]`. Then create `bundle_db` (once) and
sync:

```bash
kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -c "CREATE DATABASE bundle_db"
DIGIT_TAG=<tag> ./deploy.sh -f <yourshape>-helmfile.yaml sync
```

(list your overlay in that helmfile's `values:` after `azure-k3s.yaml`, and
the `digit-tag.yaml.gotmpl` layer, exactly as `domain-bundles-helmfile.yaml`
does — that is where `DIGIT_TAG` and the service-host overlay get applied.)

## 7. Program Kong from your manifest

Kong derives upstreams straight from the manifest — no per-bundle config:

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 &
cd <digit3>/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> \
  KONG_BUNDLE_MANIFESTS=<digit3>/src/bundles/<your>.package.yaml python3 setup.py
```

## 8. Seed + verify

`07-seed.sh` resolves account/idgen/individual endpoints by *shape*, so for a
custom grouping either run it after temporarily pointing those at your bundles,
or seed by hand against the Service that owns each: create the tenant on the
bundle with `account`, register the idgen template on the bundle with `idgen`,
create an individual on the bundle with `individual`. The verification is the
same (API plaintext / DB `vault:v1:…` + HMAC / per-tenant transit key). See
`07-seed.sh` for the exact calls.

---

## Changing a grouping later

- **Regroup** (move a service between bundles): edit the `include:` lists,
  redo steps 1–7 for the affected bundles.
- **Peel a service out to standalone** or **re-absorb** it: the detailed,
  order-sensitive procedure (build both images from one tree, flip
  `TENANT_MIGRATION_ENABLED`, sync-order vs the ingress webhook, rollout-restart
  consumers) is in **[INSTALL.md §7](INSTALL.md)** — follow it verbatim.

Data note: all bundles share `bundle_db`; switching groupings doesn't migrate
data, and the services shape's `postgres` DB is a separate dataset.
