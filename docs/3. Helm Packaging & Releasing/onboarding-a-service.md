# Onboarding a new chart

Add a new service chart to the registry. This is the DIGIT-DevOps summary of the
conventions; the full walkthrough (scaffold, every field, vendored upstream charts, new
modules, new projects) is in
[helm-charts/docs/onboarding-a-service.md](https://github.com/egovernments/helm-charts/blob/master/docs/onboarding-a-service.md).

Prerequisite: the project's `common` library is already published. For `digit3` check
`https://helm.digit.org/digit3/common` for the latest version and pin that.

## Quick start

A ready-to-fill scaffold lives at `docs/templates/service-chart/` in the chart repo.
Copy it, replace the placeholders, validate, open a PR:

```bash
cp -r docs/templates/service-chart charts/digit3/core/<service>
grep -rl __SERVICE__ charts/digit3/core/<service>        # find the placeholders

cd charts/digit3/core/<service>
helm dependency build . && helm lint . \
  && helm template test . --set global.namespace=core && rm -rf charts Chart.lock && cd -
```

## The digit3 chart conventions

These are the conventions that keep digit3 charts consistent. Follow them on any new
chart.

### Version seed 3.0.0

`Chart.yaml` seeds `version: 3.0.0`. The first publish takes it as-is; later releases
bump it from the registry, never by hand.

```yaml
apiVersion: v2
name: <service>                  # MUST match the directory and registry name; strip any "digit-" prefix
description: <one short line>     # shown on the registry site; a real sentence
type: application
version: 3.0.0                    # seed baseline
appVersion: "dev-flyway-7068862" # the REAL image tag; drives the service + <service>-db images in prod mode
dependencies:
  - name: common
    version: 3.1.1               # a common version that is ALREADY published
    repository: https://helm.digit.org/digit3/common
```

### Image tag: mode `global.mode` (prod / dev)

`global.mode` (default `prod`) decides the tag. In `prod` the tag is always
`Chart.AppVersion` and `image.tag` is ignored; in `dev` it uses `image.tag` if set. Set
`appVersion` to the real CI build tag from [Code Build](<../2. Code Build/>); never leave a
`helm create` default (`1.16.0`). Two services carry their own tags: `keycloak` and
`kong`.

### Ingress: the `gateway` flag

```yaml
ingress:
  enabled: true
  gateway: true          # route through the API gateway (renamed from the old `zuul`)
  context: "<service>"   # NO "digit-" prefix; drives the /<context> route and gateway route-path
```

The ingress backend resolves to the `kong-proxy` service by default (overridable via
`ingress.gatewayServiceName` / `ingress.gatewayServicePort` in `common`), and the
`gateway/route-path` annotation is taken from `ingress.context`.

### Context path: KEPT, derived from `ingress.context`

The app serves under a servlet context path and the gateway routes `/<ingress.context>`
to it; the two must stay in sync. Tie them together with a single overridable
`context-path` key that **derives from `ingress.context`** when blank:

```yaml
ingress:
  context: "<service>"
context-path: ""           # blank -> derives /<ingress.context>
env: |
  - name: SERVER_CONTEXT_PATH
    value: {{ index .Values "context-path" | default (printf "/%s" .Values.ingress.context) | quote }}
```

- A blank `context-path` derives `/<ingress.context>`, so the served path and the gateway
  route never drift. Override either key per environment and both move together.
- The **env-var name follows the app's `application.properties`**: most services read
  `SERVER_CONTEXT_PATH`; `account` and `workflow` read `CONTEXT_PATH`; `notify` and
  `template-config` read `SERVER_SERVLET_CONTEXT_PATH`.
- **Exception, hardcoded path:** a few apps hardcode the context-path with no `${...}`
  (`apportion`, `billing`, `idgen`, `mdms-v2`, `pg-service`, `url-shortener`). For those,
  do not add the context-path env; just set `ingress.context` to match the app's fixed
  path. The app's `application.properties` is the source of truth.

### What `common` gives a `java` service for free

Set `appType: "java"` and do **not** redefine the injected env (datasource, pool, Kafka
brokers, timezone, flyway, Tomcat threads, actuator base-path). They are centralised from
`egov-config` and the `db` Secret. Tracing is separate: set `tracing-enabled: true` to
also inject the OTel env. Full table in the
[chart repo doc](https://github.com/egovernments/helm-charts/blob/master/docs/onboarding-a-service.md).

### Service-specific env, made overridable

Put each default as a short kebab-case top-level key in `values.yaml`, reference it with
`{{ index .Values "<key>" | quote }}`, and it resolves through the three-tier merge
(common defaults < chart values < `environments/<env>.yaml` block). App-specific config
goes in the chart; shared infra (db, brokers, redis, otel endpoint) comes from
`egov-config` via `valueFrom`.

### Health checks

Use a plain `/health` path for both probes; `common` prepends `ingress.context`, so the
kubelet hits `/<context>/health`. Do not bake the context or `/actuator` into the value
or the path double-prefixes.

```yaml
healthChecks:
  enabled: true
  livenessProbePath: "/health"
  readinessProbePath: "/health"
```

## Shared config and secrets

If the service needs a new shared config key, an internal service URL, or a new Secret,
add it to `charts/digit3/cluster-configs/values.yaml` (`egov-config.data`,
`egov-service-host.data`, or `secrets:`). Per-environment values go in
`environments/<env>.yaml`, not here.

> Runtime check for chart swaps: `helm template` render-equivalence does **not** verify
> that every `configMapKeyRef` / `secretKeyRef` the chart references actually exists in
> the live ConfigMaps and Secrets. When swapping an in-cluster deployment for a published
> chart, diff the keys the chart references against the live `egov-config` and Secrets, or
> new pods fail with `CreateContainerConfigError` while old pods keep serving.

## Validate, open the PR, release

Validate locally (`helm dependency build` + `helm lint` + `helm template`), do not commit
the vendored `charts/` or `Chart.lock`, then branch off the latest `master`, commit only
your chart(s), and open a PR. One module per PR. See [access-and-use.md](access-and-use.md)
for the release form and [maintenance.md](maintenance.md) for the full SOP.
