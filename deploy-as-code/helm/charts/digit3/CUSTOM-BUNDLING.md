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
| 06 deploy | `--shape <name>` | **same script**, `--shape <path>/<name>.package.yaml` — everything shape-specific is generated (§3) |
| 07 seed | `07-seed.sh` | **same script** — 06 records which Service owns each endpoint (§4) |

A custom grouping deploys through the **same scripts** as the stock shapes: pass the manifest path where
a stock shape name would go. One command does the whole install once the images exist (§2):

```bash
cd charts/digit3/scripts
./install.sh --key <key> --domain <domain> --digit3 <digit3> \
  --shape <digit3>/src/bundles/<yourshape>.package.yaml --tag <tag> --tenant "My Tenant" --email admin@example.org
```

Built the images locally instead of publishing them (§2)? Add `--local-images`: the preflight then checks
the local docker, and the images are loaded into the node right after phase 01 — no manual import step.

or phase by phase:

```bash
./01-cluster.sh <ssh-private-key> <domain> [vm-user]   # default vm-user: azureuser
./02-secrets.sh                                        # no arguments
./03-backbone.sh                                       # no arguments
./04-vault.sh                                          # no arguments
./06-deploy.sh <digit3> <digit3>/src/bundles/<yourshape>.package.yaml <tag>
./07-seed.sh "My Tenant" admin@example.org --verify
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
(`<yourshape>.package.yaml`) — the generated helmfile, bundle values, service-host map and overlay (§3)
all key off that name. Each bundle entry is one JVM:

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
    overrides:                     # ONLY what this bundle's membership determines
      # one entry per intra-bundle call (loopback) and per CROSS-BUNDLE call,
      # parameterized so it defaults to the callee bundle's cluster-DNS name (see
      # domain-split.package.yaml: ${OTHER_BUNDLE_HOST:http://other-bundle.egov.svc.cluster.local:8080})
  # ...more bundles
```

`bundleDefaults:` (above `bundles:`) carries what every bundle in the manifest gets —
datasource and pool, Kafka, Redis, the tenant-migration switch, OTEL posture and the
canonical skip list. Copy it verbatim from a stock manifest and do NOT repeat any of it
under a bundle's `overrides:`; the generator warns when a bundle restates a
`bundleDefaults` value.

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

**One tag pins everything**: the deploy's `--tag` / `DIGIT_TAG` is used for every bundle image and its
`-db` image (via the generated bundle values) and for any service you left standalone (its ordinary
`<service>` and `<service>-db` images). Publish your bundle images at that same tag.

**Already published?** If someone built this exact manifest before, there is
nothing to build — check and skip to §3 (`docker login` first; these are
registry lookups):

```bash
for I in core-bundle other-bundle; do        # your bundle names, at the tag you will deploy with
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

## 3. Deploy: everything shape-specific is generated

`06-deploy.sh` (and `install.sh`, which calls it) runs the chart generator on your manifest. One run writes:

| Output | What it is |
|---|---|
| `charts/bundles/<bundle>/` | one Helm chart per bundle, merged from the member services' charts |
| `charts/digit3/<yourshape>-helmfile.yaml` | the shape's releases: cluster-configs, keycloak, one per bundle, gateway-kong |
| `environments/generated/<yourshape>-bundles.yaml.gotmpl` | each bundle's values: built from `environments/bundle-defaults.yaml` (`common` for every bundle, `byMember.<service>` for each bundle that includes that service — MinIO for filestore, Vault for individual, login URLs for account), domain and image tag filled in at deploy time |
| `environments/generated/<yourshape>-service-hosts.yaml` | the `egov-service-host` map: every bundled service points at its bundle; a service left out of every bundle keeps its per-service name |

If `environments/azure-k3s-<yourshape>.yaml` does not exist, 06 writes one holding only the domain. Put only
real environment choices there; never restate bundle blocks or the service-host map (the generated files are
layered last and win). Kong is then programmed from the same manifest, and 06 records the shape and the
Service owning each seeded endpoint (`scripts/.last-shape`, `scripts/.last-owners`).

To change what every bundle gets — a new env var, a different MinIO endpoint, Vault off — edit
`environments/bundle-defaults.yaml` once; it applies to every bundle of every shape on the next deploy.

**Commit** the manifest (digit3) and, in DevOps, `environments/generated/<yourshape>-*`, the helmfile,
`charts/bundles/<bundle>/` and the overlay, so the next deploy and code review see the same thing.

A service in **no** bundle is not deployed by the generated helmfile. Add its per-service release to the
helmfile by hand (copy it from `per-service-helmfile.yaml`), or put it in a bundle.

## 4. Seed + verify

Nothing extra: `07-seed.sh` reads `scripts/.last-owners` (written by 06 from the manifest) to find the
Service that owns account, idgen, individual, notification and otp, and does everything it does for the
stock shapes — tenant + realm, the fan-out wait, otp configs, idgen templates, the OTP SMS template, the
one-time admin password, and with `--verify` the Vault PII proof. `ACCOUNT_SVC=… IDGEN_SVC=…` in the
environment still override it.

```bash
./07-seed.sh "My Tenant" admin@example.org --verify
./08-token.sh MYTENANT admin@example.org '<the one-time password 07 printed>'
```

07 prints the tenant **code** (uppercased from the name, spaces removed — `"My Tenant"` → `MYTENANT`) and a
one-time admin password, shown once: capture it before moving on. Then call through kong (INSTALL.md §7).

---

## Changing a grouping later

- **Regroup** (move a service between bundles): edit the `include:` lists, regenerate the digit3
  modules (§1), rebuild the affected images (§2), and rerun `06-deploy.sh` with the manifest — charts,
  helmfile, bundle values, service-host map and Kong all follow.
- **Peel a service out to standalone** or **re-absorb** it: the detailed,
  order-sensitive procedure (build both images from one tree, flip
  `TENANT_MIGRATION_ENABLED`, sync-order vs the ingress webhook, rollout-restart
  consumers) is in **[INSTALL.md §6](INSTALL.md)** — follow it verbatim.

Data note: every shape — stock or custom — uses the same default `postgres`
database, with tenants separated by schema. Switching groupings does not
migrate or copy data; it is simply still there.
