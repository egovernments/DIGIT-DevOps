# Getting started

What you need to understand before you touch a chart: the layout, the registry, the
`common` library, and where versions come from. Full detail is in the chart repo's
[architecture.md](https://github.com/egovernments/helm-charts/blob/master/docs/architecture.md).

## The layout: project -> module -> service

```
charts/
  <project>/                 PROJECT   (e.g. digit3)
    common/                  per-project library chart (shared templates/helpers)
    <module>/                MODULE    (e.g. core, crest, studio, health, backbone)
      <service>/             SERVICE CHART (e.g. localization)
        Chart.yaml
        values.yaml
        templates/
```

- A **project** groups one product line. The first and current project is `digit3`.
- A **module** is a logical grouping of services and maps 1:1 to a **Helm repository**
  on the registry.
- A **service** is a single deployable chart. Service charts are thin: the templates
  just include `common` helpers, and almost all config is in `values.yaml`.
- **`common`** is a library chart (one per project) that every service chart depends on.

## The registry (helm.digit.org)

Two branches in the chart repo drive everything:

| Branch | Role |
|--------|------|
| `master` | source of truth: chart sources, CI workflows, registry website templates. |
| `gh-pages` | the published site at `helm.digit.org`. Machine-managed by CI; do not hand-edit except for one-off recovery. |

Each module is an independent Helm repository. Its index lives at the module root and
packages are nested one level deeper, under the chart name:

```
https://helm.digit.org/digit3/core/index.yaml
https://helm.digit.org/digit3/core/localization/localization-1.0.0.tgz
https://helm.digit.org/digit3/common/common/common-1.0.0.tgz
```

Every chart, `common` included, is nested under its own name
(`<module>/<chart>/<chart>-<version>.tgz`), so the rule stays uniform.

## The `common` library

Service charts declare `common` as a dependency pulled from the registry:

```yaml
dependencies:
  - name: common
    version: 3.1.1
    repository: https://helm.digit.org/digit3/common
```

`common` is more than shared templates; it **centralises runtime config** so every
service is wired the same way. For a `java` service it injects the datasource, the
Hikari pool, the Kafka brokers, the timezone, flyway/JPA/Tomcat settings, the actuator
base-path (all from the `egov-config` ConfigMap and the `db` Secret), and, when tracing
is enabled, the OpenTelemetry env. Services therefore do not redefine their datasource,
broker or pool; they inherit them.

Two consequences to keep in mind:

- **`common` must be published before any chart that depends on it.** A dependent's
  pinned version must already exist in the registry (CI runs `helm dependency build`).
- A service's **own** env (topics, flags, consumer groups) is made overridable through a
  three-tier merge: `common` defaults < the chart's `values.yaml` < the
  `environments/<env>.yaml` block named after the chart (highest wins).

## Shared config: `cluster-configs`

The values those injected env vars read from are defined once in the `cluster-configs`
chart: the `egov-config` ConfigMap (db URL, pool, Kafka brokers, timezone, OTel toggle,
Keycloak), the `egov-service-host` ConfigMap (internal service URLs), and the named
Secret declarations (`db`, `minio`, ...). It is installed once per product namespace,
before the services. Platform-neutral defaults live here; per-environment values are
overridden in `environments/<env>.yaml`.

## Image tags: the `global.mode` mechanism

`common.image` resolves the image tag from `global.mode` (default `prod`):

- **prod** (default): the tag is always the chart's `Chart.AppVersion`; `image.tag` in
  `values.yaml` is ignored. Set `appVersion` to the real CI build tag (e.g.
  `dev-flyway-7068862`); it drives both the service image and the `<service>-db`
  init-image.
- **dev**: uses `.Values.image.tag` if set, else falls back to `appVersion`.

In normal operation set `appVersion` and leave `image.tag` out. On digit-lts Kargo does
the pinning for you (see [Kargo Promotions](<../4. Kargo Promotions/>)): it writes the image
tag and chart version into the environment file, so you do not hand-edit either.

## How versions are derived (no per-service git tags)

- The previous version of a chart is read from the published `index.yaml`, **not** from
  git tags. There are no per-service version tags.
- A single annotated tag `"<project>/<module>/PR-<number>"` is cut per release run,
  purely for traceability back to the PR.
- Release type is chosen per PR via the form and recorded in the module
  `changelog.yaml`; it is not stored as a label on merged history.

Next: [onboarding a new chart](onboarding-a-service.md).
