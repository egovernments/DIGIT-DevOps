# How the DIGIT modulith bundling works — internals

Companion to [INSTALL.md](./INSTALL.md). That doc tells you *what to run*;
this one explains *what actually happens*: the design, what
`generate_bundle.py` emits and why each piece exists, how the bundle behaves
at runtime, and how the two container images are produced.

---

## 1. The idea

The digit3 repo contains ~17 independent Spring Boot microservices, each its
own Maven project with its own `application.properties`, DB migrations and
Docker image. The modulith work adds a **second deployment shape** for the
same, unchanged source: a chosen subset of services compiled into **one
Spring Boot process**.

Three principles drive the design:

1. **Services are sealed inputs.** No service source changes to join a
   bundle. The bundler owns every composition concern (paths, properties,
   migrations, conflicts).
2. **Composition is declarative.** One manifest (`dev-bundle.package.yaml`)
   is the single source of truth. `generate_bundle.py` regenerates the whole
   bundle module from it; nothing in the generated module is hand-edited
   (except `src/test/`, which survives regeneration).
3. **External behavior is identical.** Every service keeps its exact
   standalone URL (`/billing/v3/…`, `/idgen/v3/…`) — a caller (or kong)
   can't tell which shape is serving. Inter-service calls stay HTTP, just
   over loopback. Removing a service from the manifest and regenerating *is*
   the peel-apart back to a microservice.

Why bother: measured on this repo, 16 standalone JVMs ≈ **5,044 MB** PSS vs
the 16-service bundle ≈ **532 MB** (~9.5×), because Spring, Tomcat, JIT code
cache, GC overhead and connection pools are paid once instead of sixteen
times. This is *not* Spring Modulith and *not* a Maven multi-module reactor —
it's a generated aggregate module that depends on the services' plain jars.

---

## 2. The manifest (`src/bundles/dev-bundle.package.yaml`)

Three sections:

```yaml
bundle:                    # coordinates of the generated module
  name: dev-bundle
  groupId: org.digit.bundles
  artifactId: dev-bundle
  bootVersion: 4.0.7       # parent spring-boot-starter-parent version
  javaVersion: 25
  mainPackage: org.digit.bundles.dev
  mainClass: DevBundleApplication
  port: 8085               # the ONE server port
  outputDir: dev-bundle    # module dir, relative to the manifest

services:                  # one entry per bundled service
  - name: idgen
    module: services/idgen           # repo path — source of defaults + db/ SQL
    groupId: org.digit               # GAV of the service's PLAIN jar in ~/.m2
    artifactId: idgen
    version: 3.0.0-SNAPSHOT
    packageRoot: org.digit.idgen     # component-scan root + path-prefix predicate
    prefix: /idgen                   # = the service's standalone context-path
    basePathKey: idgen.base-path     # property feeding its literal filter patterns
    schemaTable: idgen_schema        # tenant-migration history table
    # optional: publicSchemaTable (services without tenant-migration, e.g. account),
    #           publicMigrationDirs (default [migration]; pg-service adds quartz),
    #           inProcessFlywayLocationsKey (services with their own boot-time Flyway bean)

overrides:                 # raw properties appended to application-bundle.properties
  billing.idgen.host: "http://localhost:${SERVER_PORT:8085}"   # loopback rewiring
  spring.datasource.url: "jdbc:postgresql://${DB_HOST:localhost}:${DB_PORT:5432}/${DB_NAME:bundle_db}?sslmode=${DB_SSL_MODE:disable}"
  spring.datasource.hikari.maximum-pool-size: "${DB_MAX_OPEN_CONNS:40}"      # ONE shared pool
  spring.kafka.bootstrap-servers: "${KAFKA_BROKERS:localhost:9092}"
  # …plus every explicit resolution of a cross-service property conflict
```

**Ordering matters**: tenant-migration registrations run in manifest order and
fail fast (boundary is last because its PostGIS migration fails on
extension-less databases).

`notify` is deliberately not in the manifest — it needs `--enable-preview`
and shares no platform libraries, so it runs as its own process beside the
bundle.

---

## 3. What `generate_bundle.py` emits, piece by piece

Run: `python3 src/bundles/generate_bundle.py src/bundles/dev-bundle.package.yaml`
(~340 lines of Python; regenerates everything under `src/bundles/dev-bundle/`
except `src/test/`). Six artifacts:

### 3.1 `pom.xml` — depend on the plain jars

One `<dependency>` per manifest service (its GAV), parented on
`spring-boot-starter-parent:${bootVersion}`. This only works because every
service pom on this branch configures the Boot plugin with
`<classifier>exec</classifier>`: `mvn install` then publishes **two** jars —
`<svc>-exec.jar` (the repackaged fat jar, used by the standalone shape) and
the **plain** `<svc>.jar` (ordinary classes+resources, consumable as a
dependency). Without the classifier, Boot's repackaging *replaces* the plain
jar with the fat jar, which cannot be depended on.

So the bundle's classpath is: 16 service plain jars + their (deduplicated)
transitive dependencies + Boot's own starters. Maven resolves version
conflicts among the shared libraries once, for the whole JVM.

### 3.2 The main class — one context, sixteen services

```java
@SpringBootConfiguration
@EnableAutoConfiguration
@ComponentScan(
    basePackages = { "org.digit.idgen", "org.digit.billing", …, "org.digit.bundles.dev" },
    nameGenerator = FullyQualifiedAnnotationBeanNameGenerator.class,
    excludeFilters = @ComponentScan.Filter(
        type = FilterType.ANNOTATION, classes = SpringBootConfiguration.class))
@ConfigurationPropertiesScan({ "org.digit.idgen", … })
public class DevBundleApplication { … }
```

Every clause solves a specific collision:

- **One explicit `@ComponentScan` over every service's `packageRoot`** —
  instead of sixteen `@SpringBootApplication`s, one context scans all of
  them.
- **`FullyQualifiedAnnotationBeanNameGenerator`** — default bean names are
  class *simple* names, and sixteen services predictably collide
  (`RedisConfig`, `KafkaProducer`…). FQN naming keeps identically-named
  beans from different services distinct.
- **`excludeFilters` on `@SpringBootConfiguration`** — each service still
  contains its own `@SpringBootApplication` class; scanning it would drag in
  its `@SpringBootApplication` semantics (default-package scan, duplicate
  auto-config). Excluded wholesale.
- **`@ConfigurationPropertiesScan`** — a side effect of the exclusion: each
  service's `@EnableConfigurationProperties`/`@ConfigurationProperties`
  registration lived on the excluded application class, so the bundle
  re-enables properties binding per package root.

### 3.3 `BundlePathConfig.java` — re-creating sixteen context-paths

Standalone, each service serves under `server.servlet.context-path`
(`/idgen`, `/billing`, `/employee-java`…). One servlet context has exactly
one context-path, so the bundle **blanks it** and re-creates each prefix at
the handler-mapping layer:

```java
configurer.addPathPrefix("/idgen",
        HandlerTypePredicate.forBasePackage("org.digit.idgen"));
```

— every `@Controller` under that package is mounted under that prefix.
Result: external URLs are byte-identical to standalone.

The subtlety: **servlet filters and interceptors never see handler-mapping
prefixes** — they match the raw request path literally. Services that do
literal path matching (auth filters, tenant interceptors with `/v3/…`
patterns) read their pattern base from a property; the manifest's
`basePathKey` names it, and the generator writes
`idgen.base-path=/idgen` (etc.) into the bundle properties so those literal
patterns line up with the mounted prefix.

### 3.4 The property chain — defaults, profile, overrides

For each service, the generator copies its `application.properties`
**verbatim** to `<name>-defaults.properties` in the bundle, then writes:

```properties
# application.properties (bundle)
spring.config.import=classpath:idgen-defaults.properties,classpath:billing-defaults.properties,…
spring.profiles.active=bundle
```

Precedence (low → high): imported service defaults → `application-bundle.properties`
(the active-profile document always beats imports). The profile file contains:

1. the auto section — `spring.application.name`, `server.port=${SERVER_PORT:8085}`,
   blank context-path, all the `basePathKey` assignments;
2. tenant-migration multi-registration (one entry per service, see 3.6);
3. rewired in-process Flyway locations (see 3.6);
4. **the manifest `overrides:` verbatim** — loopback hosts, the single shared
   datasource/Kafka/Hikari, and every explicit conflict resolution.

**Conflict detection**: the generator parses every imported defaults file,
groups values by key, and prints
`WARNING: unresolved property conflict` for any key where two services
disagree and no override (or auto-resolved key) decides it. At runtime
last-import-wins *silently* — which is why the README says never to ignore
these warnings: add an `overrides:` entry and regenerate. (Current state:
zero warnings.)

### 3.5 Why inter-service calls go over loopback

Each service's defaults contain host+path pairs for its dependencies
(`billing.idgen.host` + a path that already includes the callee's prefix,
e.g. `idgen/v3/…`). The overrides move only the **hosts** to
`http://localhost:${SERVER_PORT:8085}`; the paths already match the callee's
mount prefix. So billing → idgen becomes an HTTP call to the bundle's own
port: same wire protocol, same serialization, zero network hop. This keeps
services unmodified (no in-process dispatch abstraction) and preserves the
peel-apart property — point the host back at a k8s Service and the call is
remote again.

### 3.6 The `db/` tree — one namespace, two consumers

The classpath problem: sixteen jars each ship `db/migration/V*.sql`, and jar
resources **merge** on the classpath. Ten-plus services share filenames like
`V20260413193000__standardize_common_columns.sql` — same version+name,
different DDL — so same-named files would silently shadow each other.

The generator therefore copies every service's `src/main/resources/db/` SQL
subdirectories **verbatim** into a bundle-private namespace:

```
src/main/resources/db/
├── Dockerfile              # generated — the init-container image
├── migrate-all.sh          # generated — one Flyway run per service
└── sql/
    ├── idgen/migration/…           # verbatim copies, structure preserved
    ├── pg-service/migration/…
    ├── pg-service/quartz/…
    └── boundary/migration/…
```

That single tree serves **both** migration consumers:

- **Inside the bundle jar** (tenant schemas, at runtime): the
  tenant-migration library gets one registration per service —
  `digit.tenant-migration.services.<name>.schema-table=<svc>_schema` and
  `…flyway-locations=classpath:db/sql/<name>/migration` — so
  `POST /internal/migrate` with `X-Tenant-ID` runs one Flyway per service
  per tenant, each against its own history table. Services that also run
  their own public-schema Flyway bean at boot
  (notification/workflow/localization) have that bean's locations key
  (`inProcessFlywayLocationsKey`) rewired to the same private namespace —
  otherwise it would scan the *merged* `classpath:db/migration`.
- **As the init-container build context** (public schema, before the app
  starts): `db/Dockerfile` is `FROM egovio/flyway:10.7.1`, copies `sql/` in,
  and runs `migrate-all.sh` — which invokes Flyway once per service, in
  manifest order:

  ```sh
  flyway -url="$DB_URL" -user="$FLYWAY_USER" -password="$FLYWAY_PASSWORD" \
    -locations="filesystem:/flyway/sql/idgen/migration" -table="idgen_schema" \
    -schemas=public -defaultSchema=public -baselineOnMigrate=true \
    -outOfOrder=true -ignoreMigrationPatterns="*:missing" migrate
  ```

  Same image family and flags as the services' own `db-migration` init
  containers — one history table per service, so shared filenames never
  collide (each service applies *its own copy*, tracked separately).

Which copied dirs actually run is the explicit `publicMigrationDirs` knob
(default `[migration]`; pg-service declares `[migration, quartz]`). Copying
is unconditional, running is opt-in — deliberately not auto-discovered, so a
future `seed/` or `testdata/` dir under some service's `db/` can never
silently execute in a production public schema. Quartz sits inside the
bundle jar too but no tenant-migration registration references it, so it can
never run in a tenant schema.

---

## 4. Runtime picture

```
                 ┌──────────────────────────────────────────────┐
 kong (routes,   │            dev-bundle JVM  :8085             │
 strip_path=off) │  /idgen/**        → org.digit.idgen.*        │
 ───────────────▶│  /billing/**      → org.digit.billing.*      │
                 │  /employee-java/**→ org.digit.employee.*     │
                 │  …16 prefixes (BundlePathConfig)             │
                 │                                              │
                 │  billing ──HTTP──▶ localhost:8085/idgen/…    │
                 │  ONE Hikari pool → bundle_db (schemas/tenant)│
                 │  ONE Kafka client set, ONE Redis client      │
                 └──────────────────────────────────────────────┘
   init container (dev-bundle-db): 16 sequential public-schema Flyway runs
```

- One Tomcat, one port; every service answers at its standalone path.
- One shared datasource (`bundle_db`) sized once
  (`DB_MAX_OPEN_CONNS`, default 40) instead of sixteen pools.
- `POST /internal/migrate` (tenant migration) is served by the bundle but
  deliberately has **no kong route** — reachable only in-cluster.

---

## 5. How the images are built

Two images per bundle, always tagged as a pair.

### 5.1 App image (`egovio/dev-bundle:<tag>`)

`mvn package` in the bundle module produces
`target/dev-bundle-1.0.0-SNAPSHOT.jar` — a normal Boot fat jar containing the
16 plain service jars under `BOOT-INF/lib/` plus the generated
main/path-config classes and the whole property + `db/sql` resource tree.

Two ways to containerize it:

- **Repo way** (`build/maven/Dockerfile`, used by CI for every service):
  two-stage — `amazoncorretto:25` + Maven compiles the module inside the
  build stage, runtime stage copies `target/*.jar` and runs it via
  `start.sh`. Caveat on this branch: the exec-classifier change means
  `target/` now holds *two* jars (`*.jar` plain + `*-exec.jar` fat), so the
  `COPY target/*.jar` glob must be narrowed to `*-exec.jar` for services —
  the bundle module itself doesn't set the classifier, so it still produces
  a single executable jar.
- **Runtime-only way** (what the modulith k3s deploy used — jar already
  built on the workstation):

  ```dockerfile
  FROM amazoncorretto:25
  WORKDIR /opt/egov
  COPY app.jar /opt/egov/app.jar
  EXPOSE 8085
  CMD ["sh", "-c", "exec java $JAVA_OPTS -jar /opt/egov/app.jar"]
  ```

  Built with `docker buildx build --platform linux/amd64` (the Mac is arm64,
  the node amd64 — a pure-COPY build cross-compiles instantly), then loaded
  into the single-node k3s without any registry:
  `docker save … | ssh <vm> 'sudo k3s ctr images import -'` with
  `pullPolicy: IfNotPresent`.

  `JAVA_OPTS` and `SERVER_PORT` come from the chart (heap percentages, port
  8085), which is why the CMD goes through `sh -c`.

### 5.2 DB init image (`egovio/dev-bundle-db:<tag>`)

Entirely generator-owned. The build context **is** the generated
`src/main/resources/db/` directory (Dockerfile + `migrate-all.sh` +
`sql/`): `FROM egovio/flyway:10.7.1`, ~200 MB. At pod start it runs the 16
sequential Flyway invocations from §3.6 against `$DB_URL` and exits; the app
container starts only after it succeeds.

Why a combined image beats listing the sixteen per-service `egovio/<svc>-db`
images as init containers (the documented fallback): **composition
atomicity** — adding/removing a manifest service regenerates jar deps,
prefixes, properties *and* the migration set in one commit, no Helm
`initContainers:` list to keep in lockstep; and **version locking by
construction** — the image copies migrations from the same source tree that
built the bundled jars, so DDL and code cannot disagree the way sixteen
independently-tagged images can.

### 5.3 Chart-side: `generate_bundle_chart.py` (this repo)

A second generator (`deploy-as-code/helm/bundler/`) consumes the **same
manifest** and produces `charts/bundles/dev-bundle/`: it `helm template`s
each member service's existing chart, harvests the fully-resolved container
env and db-migration init-container config, merges them under
`merge-rules.yaml` (drops per-service `SERVER_PORT`/`JAVA_OPTS`/datasource
env that would fight the bundle's property chain, plus harvested pool knobs
like the Go-duration `DB_CONN_MAX_LIFETIME`), and emits one `common`-based
chart whose env is a **map** (so environments can deep-merge single
variables) with all 16 route prefixes in `ingress.contexts`. One manifest →
one jar, one migration image, one chart.

---

## 6. Change workflow

| Change | Do |
|---|---|
| Service code changed | `mvn install` the service → regenerate → rebuild bundle |
| Add a service | manifest entry → regenerate → resolve any new conflict warnings → rebuild |
| Remove a service | delete its manifest entry → regenerate (that *is* the peel-apart) |
| New bundle flavor | copy the manifest (new `outputDir` + port) → generate a second module |
| Anything under `dev-bundle/` except `src/test/` | never edit by hand — it's generator-owned |
