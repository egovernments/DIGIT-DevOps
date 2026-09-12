# How the Helm bundling works — `generate_bundle_chart.py` internals

Third doc in the set: [INSTALL.md](./INSTALL.md) is the runbook,
[BUNDLING.md](./BUNDLING.md) explains how the *application* bundle (one JVM)
is generated in the digit3 repo. This one explains the DevOps half: how the
16 per-service Helm charts are merged into the single
`charts/bundles/dev-bundle` chart — what the generator does, the merge
policy, what the output chart looks like, and how environments override it.

---

## 1. The problem it solves

When 16 services collapse into one deployment, their 16 charts must collapse
too — but those charts are not trivial to merge by hand:

- each carries a large `env: |` **string block** (a Go-template string, not
  structured YAML) with per-service DB/Kafka/Redis/host wiring;
- many env values would now be *wrong* (per-service `SERVER_PORT`,
  `JAVA_OPTS`, context paths, datasource URLs) or *conflicting*
  (`LOG_LEVEL: info` vs `DEBUG`, kafka vs redis pub/sub);
- each chart ships its own `db-migration` init container that still has to
  run for its schema set;
- and hand-merging would rot the moment the bundle's composition changes.

So the chart merge is generated, from the **same manifest** that generates
the application bundles (`bundles.package.yaml` in the digit3 repo — a
catalog of services plus one or more compositions). One manifest edit →
regenerate jar, migration image, *and* chart. Nothing merged by hand,
nothing to keep in lockstep. One run emits a chart per composition — the
modulith branch's manifest yields `dev-bundle`; the domain-split branch's
yields `identity-bundle`, `notification-bundle`, `billing-bundle` and
`admin-bundle`.

```bash
cd deploy-as-code/helm/bundler
python3 generate_bundle_chart.py --manifest <digit3>/src/bundles/bundles.package.yaml
# optional: --charts-root, --rules merge-rules.yaml, --output (single-bundle manifests only)
# output default: charts/bundles/<bundle.name>, one per composition
```

Inputs: the manifest (service list + optional `helm:` policy extension),
`bundler/merge-rules.yaml` (the DevOps-side default policy), the existing
per-service charts under `charts/*`, and the `common` library chart.
Everything under the output chart is generator-owned — edit the manifest or
the rules and re-run.

---

## 2. The pipeline, step by step

### 2.1 Resolve each service to a chart

For every manifest service, the generator searches the chart groups for
`<name>-java` first, then `<name>` (so `idgen` → `idgen-java`,
`apportion` → `apportion`) — with `charts/digit3` searched before every
other group. That ordering is load-bearing: legacy groups
(`core-services`, `accelerators`, …) carry same-named charts from older
stacks with reference-cluster values baked in, and plain alphabetical
order used to harvest those. Missing chart = hard error before any work
happens.

### 2.2 Render each member chart for real (`helm template`)

The interesting design choice: it does **not** parse chart values — it
`helm template`s each chart (deployment.yaml only) in a scratch copy with
the `common` chart vendored in, using placeholder `image.tag=SCRATCH` etc.
That means every `env: |` string resolves through the exact same template
machinery (`common.name` env-merge, `{{ .Values.… }}` substitutions) it
would at deploy time — the harvest sees the *effective* env, not the raw
text. From the rendered Deployment it extracts:

- the **main container's `env` list** (name → `value` or `valueFrom`), and
- the **`db-migration` init container** (image repository + its env:
  `DB_URL`, `SCHEMA_TABLE`, `FLYWAY_*`, …), skipped with a report note if
  the chart doesn't enable one.

It also compares each chart's `ingress.context` against the manifest
`prefix` and reports **EXTERNAL PATH CHANGES** when they differ (e.g. a
chart that served `/individuals` while the bundle serves
`/individuals-java`) — those are the cases where kong routes/clients must
move.

### 2.3 Merge the envs under policy

All 16 env lists are merged **in manifest order** into one map. For each
variable, in order:

1. **Drop rules** (`merge-rules.yaml drop:`, exact `name:` or regex
   `pattern:`) — removed, with the reason recorded in the report.
2. **Loopback detection** (hardcoded, not a rule): any env whose value is a
   `configMapKeyRef` into `egov-service-host` for a *bundled* chart name, or
   a literal `http(s)://<bundled-chart>…` URL, is dropped. Rationale: the
   bundle **jar** already rewires those calls to `localhost` via its
   property overrides — a surviving env var would silently win over that
   property and route in-JVM calls back over the network.
3. **First writer wins** for identical values; a later different value is:
   - replaced by the **`resolve:`** entry if one exists (recorded as
     "resolved by rule"), or
   - reported as an **UNRESOLVED CONFLICT** — generation still succeeds,
     first-in-manifest-order wins *loudly*, and the fix is a `resolve:`
     entry (or `helm.resolve` in the manifest).
4. Finally **`contractEnv:`** entries are stamped over everything — the
   bundle's documented env contract, matching the `${VAR:default}`
   placeholders its `application-bundle.properties` reads.

The manifest may carry a `helm:` section with its own
`drop`/`resolve`/`contractEnv` that extends/overrides `merge-rules.yaml` —
bundle-specific policy lives with the bundle, repo-wide policy in the rules
file.

### 2.4 What the policy actually says (and why)

`drop:` falls into seven themes — each entry keeps a `reason:` that the
report echoes:

| Theme | Vars | Why |
|---|---|---|
| One server | `SERVER_PORT`, `*CONTEXT_PATH*`, `HTTP_PORT`, `PORT` | the bundle renders one `SERVER_PORT` from `.Values.httpPort`; prefixes are handled inside the jar |
| One heap | `JAVA_OPTS`, `JAVA_ENABLE_DEBUG`, `JAVA_ARGS` | one JVM = one arg line, rendered from `.Values.heap` |
| Tenant migration | `TENANT_MIGRATION_*`, `^SCHEMA_SEPARATION_`, `^MIGRATION_` | per-service schema tables are baked into the bundle jar; only a single global enable switch survives (contract env) |
| Datasource | `SPRING_DATASOURCE_URL/USERNAME/PASSWORD`, `SPRING_FLYWAY_ENABLED` | the bundle composes ONE datasource from discrete `DB_*` contract envs; a Spring-dialect env would override that property JVM-wide |
| Pool sizing | `DB_CONN_MAX_LIFETIME`, `DB_MAX_OPEN_CONNS`, `DB_MAX_IDLE_CONNS` | one shared Hikari pool, sized by contract envs — and individual's Go chart ships `15m` (a Go duration) where the Java property expects seconds and appends `000` → `"15m000"`, `NumberFormatException` at boot (found the hard way) |
| Observability | `^MANAGEMENT_`, `OTEL_*` switches, `^JAEGER_`, `PROMETHEUS_PORT` | one JVM = one observability posture, via `OTEL_*` contract envs; per-service Boot management switches apply context-wide and fight |
| Per-service identity | `KAFKA_CONSUMER_GROUP`, `REDIS_CONSUMER_GROUP/ID`, `MESSAGE_BROKER_ENABLED` | each service's own value ships inside the jar's `<svc>-defaults.properties`; one env var would collapse them all to a single value across the JVM |

`resolve:` documents every real cross-service disagreement and the choice
made: `PUBSUB_TYPE=kafka` (account said redis — but account-migration must
reach the in-JVM tenant-migration consumer, which follows
`tracer.pubsub.type`), `KEYCLOAK_BASE_URL` in-cluster (employee pointed at
the public digit-lts URL), `LOG_LEVEL=info` (workflow info vs account
DEBUG), `VAULT_HOST` from the service-host configmap (otp hardcoded a
namespace URL).

`contractEnv:` is the bundle's stable configuration surface — `DB_HOST/NAME`
from `egov-config`, `DB_USER/PASSWORD` from the `db` secret, `KAFKA_BROKERS`
from `egov-config`, `REDIS_HOST/PORT`, `PUBSUB_TYPE`, and conservative-off
switches (`TENANT_MIGRATION_ENABLED=false`, `OTEL_ENABLED=false`). These
exactly mirror the `${DB_HOST:localhost}`-style placeholders in the bundle
jar's properties, and every one is per-environment overridable.

---

## 3. The emitted chart

Output (`charts/bundles/dev-bundle/`): `Chart.yaml`, `values.yaml`, three
templates, and `env-block.sample.yaml`. All banner-stamped
"GENERATED … do not edit".

### 3.1 Still a `common`-family chart

`Chart.yaml` depends on `common` 0.0.5 (`file://../../common`) — so the
bundle chart gets the same `common.name` env-merge (its `dev-bundle:` block
in the environment file overrides everything), `common.labels`, and
`common.image` (registry prefixing + "Tag is mandatory") as every other
DIGIT chart. It behaves like one big service chart, not a new species.

### 3.2 `values.yaml` — env is a MAP, not a string block

The one deliberate departure from the per-service chart convention:

```yaml
env:
  DB_NAME:
    valueFrom: {configMapKeyRef: {name: egov-config, key: db-name}}
  VAULT_ENABLED:
    value: 'true'
  …(~200 merged vars)
```

Per-service charts hold env as one `env: |` template **string**, which an
environment file can only replace *wholesale*. A YAML **map** deep-merges
through Helm's value layering, so an environment can override exactly one
variable — or delete one by setting it to `null`:

```yaml
# environments/azure-k3s.yaml
dev-bundle:
  env:
    LOG_LEVEL: {value: debug}            # override one var
    VAULT_ENABLED: {value: "false"}      # override another
    SOME_VAR: null                       # remove entirely
```

The deployment template iterates the map and emits `value:` or `valueFrom:`
per entry; `JAVA_OPTS` and `SERVER_PORT` are not in the map — they render
from `.Values.heap` / `.Values.httpPort`.

Also in values: `replicas: 1`, `httpPort` from the manifest,
resources sized from the **measured bundle footprint** (requests 500m/1Gi,
limits 2/2Gi) rather than the sum of 16 per-service requests, health checks
present but disabled by default, and the ingress block below.

### 3.3 Init containers: ordered map, two modes

```yaml
dbMigrationOrder: [idgen, template-config, billing, …]   # manifest order
dbMigrations:
  idgen:
    enabled: true
    image: {repository: idgen-java-db, tag: ''}
    env: {DB_URL: …, SCHEMA_TABLE: {value: idgen_schema}, FLYWAY_USER: …}
```

The deployment template ranges over `dbMigrationOrder` and emits one init
container per entry — the harvested per-service `egovio/<svc>-db` images
with their exact env. That's the generated **default (fallback) mode**: no
new image pipeline needed, Kubernetes runs them sequentially.

Because `dbMigrationOrder` is a *list* (replaced wholesale on merge, unlike
maps), an environment can switch to the **combined-image mode** — what
azure-k3s runs — without touching the chart:

```yaml
dev-bundle:
  dbMigrationOrder: [combined]           # list replaces the 16-entry default
  dbMigrations:
    combined:                            # map deep-merge just adds this key
      enabled: true
      image: {repository: dev-bundle-db, tag: modulith-<sha>}
      env:
        DB_URL: {value: "jdbc:postgresql://postgresql-lts.egov:5432/postgres"}
        FLYWAY_USER: {valueFrom: {secretKeyRef: {name: db, key: flyway-username}}}
        FLYWAY_PASSWORD: {valueFrom: {secretKeyRef: {name: db, key: flyway-password}}}
```

The 16 harvested entries remain in the merged values but are never iterated
(the order list no longer names them). One override block = one init
container running the generated `dev-bundle-db` image (see BUNDLING.md §5.2
for why combined beats per-service: composition atomicity + version locking).

### 3.4 Ingress: one object, sixteen paths, kong stays in front

```yaml
ingress:
  enabled: true
  zuul: true
  contexts: [idgen, template-config, billing, …, employee-java, individuals-java, accounts, boundary]
```

The ingress template ranges over `contexts` and — because `zuul: true`, same
as every per-service chart — points **every path at `kong-kong-proxy:8000`**,
with TLS from the shared `<domain>-tls-certs` secret. So nginx still funnels
everything to kong; kong's own routes decide the upstream, which is why the
deploy runbook re-runs `setup.py` with `KONG_BUNDLE_UPSTREAM` after
switching shapes. The prefixes replace, path-for-path, the Ingresses the 16
uninstalled service releases used to publish — which is exactly why the two
shapes cannot coexist.

(Historical note: the ingress template's first line is
`{{- if .Values.ingress.enabled }}` — it originally ended `-}}`, which
trimmed the following newline and glued `apiVersion:` onto the generated
comment banner, yielding an Ingress with no apiVersion. Fixed in the
generator; symptom was helm's "error validating data: apiVersion not set".)

### 3.5 `env-block.sample.yaml`

A ready-to-paste starter for `environments/<env>.yaml`: the `dev-bundle:`
block skeleton with the image tag placeholders and one `dbMigrations` entry
per service. The real azure-k3s block grew from this plus the overrides in
INSTALL.md §2.3.

---

## 4. The generation report — read it every run

The generator ends with a report; it is the merge's audit trail:

- **services merged** and any **missing db-migration** charts;
- **EXTERNAL PATH CHANGES** — chart context vs manifest prefix (kong/client
  action required);
- **dropped env vars** — every var, which services carried it, and the rule
  reason;
- **conflicts resolved by rule** — what `resolve:` decided and between whom;
- **UNRESOLVED CONFLICTS** — first-in-manifest-order won; treat these like
  the app generator's property warnings: add a `resolve:` entry and re-run
  rather than trusting ordering;
- **reminders** — the three integration points outside the chart: Argo CD
  application list, `egov-service-host` keys for merged services →
  `http://dev-bundle.egov.svc.cluster.local:8080/`, and kong routes → the
  bundle Service.

Current dev-bundle run: 66 dropped vars, 7 rule-resolved conflicts, 0
unresolved.

---

## 5. How it all layers at deploy time

```
merge-rules.yaml ─┐
manifest helm: ───┤→ generate_bundle_chart.py → charts/bundles/dev-bundle (values: env map, defaults)
16 member charts ─┘                                      │ helm value layering (helmfile release):
                                                         │   azure-k3s-secrets.dec.yaml
                                                         │   azure-k3s.yaml  ← dev-bundle: block deep-merges env,
                                                         │                     replaces dbMigrationOrder, pins tags
                                                         ▼
                                            rendered Deployment/Service/Ingress
```

The helmfile release (`digit3services-helmfile.yaml`) points at
`../bundles/dev-bundle` and passes the secrets + environment files; the
`common.name` helper merges the environment's `dev-bundle:` block over the
generated values with highest precedence. Maps (env, dbMigrations) deep-merge
per key; scalars and **lists** (dbMigrationOrder) replace — that asymmetry is
what makes both the single-var override and the combined-init-container
switch possible from the environment file alone.

## 6. Regeneration workflow

| Change | Do |
|---|---|
| Bundle composition changed (manifest) | re-run the generator; review the report; update kong + service-host per reminders |
| A member chart's env/init config changed | re-run the generator (it re-renders the charts); diff `values.yaml` |
| Env var wrong for one environment | don't regenerate — override in that environment's `dev-bundle:` block |
| Var should never be harvested | add a `drop:` (or `resolve:`/`contractEnv:`) entry in merge-rules.yaml, regenerate |
| Anything under `charts/bundles/dev-bundle/` | never hand-edit — generator-owned |
