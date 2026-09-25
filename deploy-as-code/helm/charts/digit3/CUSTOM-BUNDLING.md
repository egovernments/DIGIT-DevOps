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
of 05–06:

```bash
cd charts/digit3/scripts
./01-cluster.sh <ssh-private-key> <domain> [vm-user]   # default vm-user: azureuser
./02-secrets.sh                                        # no arguments
./03-backbone.sh                                       # no arguments
./04-vault.sh                                          # no arguments
```

They are idempotent and identical to a stock install — details and failure
modes in [INSTALL.md](INSTALL.md) §1.2–§1.8.

**Paths below** are relative to `DIGIT-DevOps/deploy-as-code/helm/` unless they
start with `<digit3>`: `environments/` sits there, the helmfiles and scripts are
one level down in `charts/digit3/`.

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

## 2. Get the images

Each bundle needs its app image **and** its db-migration image, and both must
come **from the same digit3 tree** (a db image from another tree fails Flyway
checksum validation). A bundle's tag is free-form — any string works, as long
as both of its images carry it.

**Services you left standalone need images too**: their ordinary per-service
`<service>` and `<service>-db` images, at the tag you pass as `DIGIT_TAG` in
§6. Note the split — `DIGIT_TAG` pins the standalone (and any stock) images;
a custom bundle's tag is set explicitly in §4 and need not match.

**Already published?** If someone built this exact manifest before, there is
nothing to build — check and skip to §3 (`docker login` first; these are
registry lookups):

```bash
for I in core-bundle other-bundle; do        # your bundle names, tag from §4
  for T in $I $I-db; do docker manifest inspect egovio/$T:<bundle-tag> >/dev/null 2>&1 \
    && echo "ok $T" || echo "MISSING $T"; done
done
for I in billing apportion pg-service; do    # your standalone services, tag = DIGIT_TAG
  for T in $I $I-db; do docker manifest inspect egovio/$T:<DIGIT_TAG> >/dev/null 2>&1 \
    && echo "ok $T" || echo "MISSING $T"; done
done
```

Otherwise build the bundle images, either way below. Standalone services use
the published per-service images and are never built here.

**Publish through the Actions pipeline** (the way the stock bundles are built —
`digit3/src/bundles/README.md` §5): register the pair in `build/build-config.yml`
(one entry per bundle: the app image from `src/bundles/<bundle>`, the `-db`
image from `src/bundles/<bundle>/src/main/resources/db`) and add the bundle
name to the `service` dropdown in `.github/workflows/build.yaml`; push; run
the workflow for each bundle. The images appear on Docker Hub as
`egovio/<bundle>:<branch>-<sha>` and `egovio/<bundle>-db:<branch>-<sha>`, and
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
cd <DIGIT-DevOps>/deploy-as-code/helm
python3 bundler/generate_bundle_chart.py --manifest <digit3>/src/bundles/<yourshape>.package.yaml
# → charts/bundles/<each bundle in the manifest>; read the generation report
```

Each chart also gets an `env-block.sample.yaml`. Ignore its `dbMigrations:`
section — it lists one migration per member service, while a bundle deploys a
single **combined** init image. §4 below is the form to use.

## 4. Add an env block per bundle

In `environments/azure-k3s.yaml`, add one block per custom bundle. **Copy a
whole existing bundle block and edit only the items below.** The rest of it is
required boilerplate that this list does not repeat — `namespace: egov`,
`dbMigrationOrder: [combined]`, `dbMigrations.combined.enabled: true`, and the
`FLYWAY_USER`/`FLYWAY_PASSWORD` `secretKeyRef`s into the `db` secret.

Pick the block to copy by what your bundle holds: `identity-bundle:` has
`VAULT_ENABLED` but no minio settings, `admin-bundle:` has minio but no
`VAULT_ENABLED`, and `dev-bundle:` is the only one carrying **both** — copy
that one for a bundle holding `filestore` *and* `individual`/`otp`.
What you change:

- `image.repository: <bundle>` + `pullPolicy: IfNotPresent`, and the same for
  the `dbMigrations.combined` image (`<bundle>-db`).
- **Tags.** Stock bundles get their tag from `environments/digit-tag.yaml.gotmpl`
  (`DIGIT_TAG`); a custom bundle name is not in that file. Two options, and the
  right one depends on your grouping:
  - **Everything in some bundle, all images from one build** → add your bundles
    to `digit-tag.yaml.gotmpl`: one tag source, and `DIGIT_TAG=<tag>` pins them.
  - **Any service left standalone** (or bundle images built separately from the
    per-service ones) → **add** these two keys to the block (no stock block has
    them — they all take their tag from the file above):
    ```yaml
      image: { repository: "<bundle>", tag: "<bundle-tag>", pullPolicy: IfNotPresent }
      dbMigrations: { combined: { image: { repository: "<bundle>-db", tag: "<bundle-tag>" } } }
    ```
    `digit-tag.yaml.gotmpl` applies one tag to
    every entry, and `DIGIT_TAG` is already pinning your standalone services'
    images; putting the bundle in that file would demand a bundle image at the
    standalone services' tag, which does not exist.
- `dbMigrations.combined` `DB_URL: jdbc:postgresql://postgresql-lts.egov:5432/postgres`
  — every shape uses the cluster's default `postgres` database; tenants separate
  by schema. No database to create.
- `TENANT_MIGRATION_ENABLED: "true"` (each bundle consumes tenant events for
  its own services). Standalone services already set this in their per-service
  charts — nothing to add, but every migrating service must have it or §8's
  fan-out gate never completes.
- **On the bundle that includes `filestore`**: the minio S3 overrides
  (`S3_ACCESS_KEY`/`S3_SECRET_KEY` from the `minio` secret, `S3_ENDPOINT`,
  `S3_USE_SSL: "false"`).
- **On the bundle that includes `individual`/`otp`**: `VAULT_ENABLED: "true"`
  (the role/secret/HMAC refs are chart defaults; needs §1.8 Vault).

## 5. Write a shape overlay

The stock shapes each have an overlay (`environments/azure-k3s-<shape>.yaml`)
that sets the domain, an `egov-service-host` key for every **bundled** service
that has one, and each bundle's `KEYCLOAK_PUBLIC_BASE_URL`. Copy
`environments/azure-k3s-domain-bundles.yaml` to
**`environments/azure-k3s-<yourshape>.yaml`** (same stem as the manifest) and:

- set `global.domain`;
- for every **bundled** service that has an `egov-service-host` key, set it to
  `http://<the-bundle-that-includes-it>.egov.svc.cluster.local:8080/`. Only 13
  of the 16 have a key — `account`, `url-shortener` and `pg-service` have none,
  and nothing resolves them by host key, so do not invent one;
- leave a **standalone** service's key alone: the base `azure-k3s.yaml` already
  points it at its own per-service DNS name, which is where it still runs;
- give each bundle block `KEYCLOAK_PUBLIC_BASE_URL: https://<domain>/keycloak`
  and `URL_SHORTENER_HOST_NAME: https://<domain>`.

Because the overlay carries the manifest's stem, the chart generator's drift
check compares it against the composition on every run and warns if a key
points at the wrong bundle — name it anything else and the check silently
skips. (The two stock manifests are remapped to their topology names,
`dev-bundle`→`single-container` and `domain-split`→`domain-bundles`; a custom
manifest's stem is used as-is.) The check prints **only on mismatch**, so
silence in the generation report means no drift, not a skipped check.

This map carries **both directions**, which matters as soon as anything is
left standalone. Inbound is obvious: a key names where that service now lives.
Outbound is the part to know — each per-service chart reads its *callees'*
hosts from these same keys (`billing`'s `BILLING_IDGEN_HOST`, `pg-service`'s
`IDGEN_HOST`/`REGISTRY_HOST`/`INDIVIDUAL_HOST`, …, all `configMapKeyRef`s into
`egov-service-host`). So repointing a bundled service's key is exactly what
lets a standalone service find it inside the bundle. No per-service override
is needed, and `overrides:` in the manifest (§1) covers only bundle-to-bundle
calls.

The map reaches the cluster through the `cluster-configs` release your
helmfile lists first (§6) — the backbone helmfile syncs that release with base
values only, so there is no separate re-sync step: the §6 sync applies it.

**Re-run §3's generator command now.** The drift check reads this overlay, and
at §3 it did not exist yet, so that first run had nothing to compare and its
silence meant nothing. This second run is the one whose silence means no drift.

## 6. Write a helmfile for your bundles

Copy `charts/digit3/domain-bundles-helmfile.yaml` to
`charts/digit3/<yourshape>-helmfile.yaml` (its `../../environments/…` refs
already resolve from there), repoint **every**
`azure-k3s-domain-bundles.yaml` reference at your overlay — there are four
kinds of release carrying it: `cluster-configs`, `keycloak`, each bundle and
`gateway-kong` — and list
**your** bundle releases (each `chart: ../bundles/<name>`) plus `gateway-kong`.
If your grouping leaves any service out of every bundle, add its per-service
release too — otherwise it is simply never deployed. No shipped helmfile mixes
the two, so copy the release block from `per-service-helmfile.yaml` verbatim
and change only the overlay path. Keep its **five** `values:` entries: a
per-service block inserts `./<service>/values.yaml` between the overlay and
`digit-tag.yaml.gotmpl`, where a bundle block has only four.
Keep `cluster-configs` first with `keycloak` needing it (it carries your
overlay's `egov-service-host` map), and give **every** bundle
`needs: [keycloak/keycloak]` — helmfile syncs concurrently, and the bundles need
Keycloak's realm endpoints. Keep each bundle's `values:` in the stock order —
`azure-k3s-secrets.dec.yaml`, `azure-k3s.yaml`, your overlay,
`digit-tag.yaml.gotmpl` — that is where `DIGIT_TAG` is applied. Then sync:

```bash
export KUBECONFIG=$HOME/modulith-kubeconfig.yaml   # 01-cluster.sh printed the path
DIGIT_TAG=<tag> ./deploy.sh -f <yourshape>-helmfile.yaml sync
for b in core-bundle other-bundle billing apportion pg-service; do   # bundles AND standalone services
  kubectl rollout status deploy/$b -n egov --timeout=900s; done
kubectl rollout status deploy/kong-kong -n egov --timeout=600s
echo <yourshape> > scripts/.last-shape    # so a later 04-vault.sh re-sync keeps your overlay
```

`DIGIT_TAG` is mandatory (`requiredEnv` fails the deploy without it) even if
you set explicit tags in §4 — it also pins any stock images the helmfile lists.

The numbered scripts read `KUBECONFIG` from `scripts/.env`; the raw `kubectl`
and `helmfile` lines in §6–§8 are outside them, so export it once as above or
they talk to the wrong cluster (or none).

Keycloak may still be starting when those rollouts finish — `needs:` orders the
sync, not readiness. Nothing here waits for it, and nothing has to: `07-seed.sh`
opens by waiting on Keycloak's admin API.

## 7. Program Kong from your manifest

Kong derives upstreams straight from the manifest — no per-bundle config. Kong
must be Running first (the rollout wait above; nothing else waits for it on
this path):

```bash
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 >/dev/null 2>&1 & PF=$!
trap 'kill $PF 2>/dev/null' EXIT          # survives a setup.py failure too
until curl -sf http://localhost:18001/status >/dev/null; do sleep 1; done
cd <digit3>/src/services/kong
KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS=<domain> \
  KONG_BUNDLE_MANIFESTS=<digit3>/src/bundles/<yourshape>.package.yaml python3 setup.py
curl -s http://localhost:18001/services | python3 -c \
  'import sys,json,collections; c=collections.Counter(s["host"] for s in json.load(sys.stdin)["data"]); [print(n, h) for h,n in c.items()]'
kill $PF       # a leftover forward is what makes the next run fail on a bound port
```

Routes and plugins are the same for every shape; only each service's upstream
host changes. A service in no bundle keeps its per-service upstream.

`setup.py` derives each *upstream* from your manifest, but it only knows the
*routes* it already carries. A grouping that includes a **service kong has
never seen** — anything outside the 16-service catalog, e.g. a module a team
added to a bundle — hard-exits with `… includes '<svc>' which has no kong
service entry '<svc>' — add it to SERVICES/ROUTES first`. Add it to the
`SERVICES` map and a route to `ROUTES` in `digit3/src/services/kong/setup.py`
before you reach this step: the manifest decides where a route points, it
cannot create one.

Alongside the catalog services, `setup.py` always programs a few fixed routes
that no manifest mentions — `keycloak`, `mdms-v2` and `account-config` — so the
service count it reports is higher than your member count. Every `KONG_*`
parameter, with defaults and per-shape examples:
`digit3/src/services/kong/README.md`.

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
./08-token.sh MYTENANT admin@example.org '<the one-time password 07 printed>'
```

07 prints the tenant **code** (uppercased from the name, spaces removed —
`"My Tenant"` → `MYTENANT`) and a one-time admin password. Both are positional
arguments to `08-token.sh` — it has no terminal to prompt on in a script — and
the password is shown once: capture it before moving on. Then call through kong
(INSTALL.md §7).

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
