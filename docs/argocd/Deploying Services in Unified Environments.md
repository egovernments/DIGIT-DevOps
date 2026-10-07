# Deploying Services in Unified Environments

How to get a service running in `unified-dev`, `unified-qa` or `unified-uat`
using Argo CD.

Written for someone outside the DevOps team who needs to deploy a service and
does not already know how this repo is wired. Everything here is a change to
git — **you do not need cluster access to deploy.**

## Contents

- [1. What you need before you start](#1-what-you-need-before-you-start)
- [2. How a deployment actually happens](#2-how-a-deployment-actually-happens)
- [3. The layout](#3-the-layout)
- [4. Add a service to an existing namespace](#4-add-a-service-to-an-existing-namespace)
- [5. Deploy into a new namespace](#5-deploy-into-a-new-namespace)
- [6. Configuration and secrets](#6-configuration-and-secrets)
- [7. Verify your deployment](#7-verify-your-deployment)
- [8. When something does not work](#8-when-something-does-not-work)
- [9. Checklists](#9-checklists)

---

## 1. What you need before you start

| | |
|---|---|
| Branch | **`unified-env-lts`** — all three unified environments track it |
| Repo | `https://github.com/egovernments/DIGIT-DevOps.git` |
| Access | Write access to the repo (via PR). Cluster access is **not** required to deploy |
| For secrets | Someone with SOPS decrypt rights — see §6.2 |

> **One branch, three environments.** `unified-dev`, `unified-qa` and
> `unified-uat` all track `unified-env-lts`. They differ only by which
> `environments/<env>.yaml` file each Application reads. A change to a shared
> file affects all three; a change to an environment file affects one.

---

## 2. How a deployment actually happens

Each cluster runs a root **app-of-apps** (`<env>-bootstrap`) that watches
`charts/argo-cd/<env>/`. Everything follows from that:

```
you push to unified-env-lts
   -> <env>-bootstrap syncs charts/argo-cd/<env>/
      -> the ApplicationSet picks up your new list element
         -> Argo CD creates an Application for your service
            -> that Application renders the Helm chart and applies it
```

Three consequences worth internalising:

- **No `kubectl apply` step.** Adding a service is a git change. If you have
  been told to apply appsets by hand, that is out of date.
- **A service is not an Argo CD Application you write.** You add a one-line
  *element* to an existing ApplicationSet, which generates the Application for
  you. Hand-written Applications are reserved for third-party charts.
- **Sync is automatic** (`selfHeal: true`), typically within a minute or two.

---

## 3. The layout

Four places matter. A deployment is usually a change to two of them.

```
deploy-as-code/helm/
├── charts/
│   ├── argo-cd/<env>/<domain>/     WHERE it is deployed   (appsets + AppProject)
│   │   ├── <domain>-app-project.yaml
│   │   └── <domain>-app-set-*.yaml
│   ├── core-services/<svc>/        WHAT is deployed       (the Helm charts)
│   ├── health-services/<svc>/
│   ├── studio-services/<svc>/
│   ├── backbone-services/<svc>/
│   ├── frontend/<svc>/
│   └── cluster-configs/            namespaces + secrets
└── environments/
    ├── unified-<env>.yaml          per-environment config
    └── unified-<domain>-<env>.yaml per-domain config
```

**Domains** group services that share a namespace and an AppProject. A domain
may draw from several chart families — which family a service belongs to is
decided by the appset you add it to, not by the domain:

| Domain | Namespace(s) | Chart families | dev | qa | uat |
|---|---|---|---|---|---|
| `egov` | `egov` | `core-services`, `business-services`, `common-services`, `frontend` | ✓ | ✓ | ✓ |
| `health` | `health`, `sso` | `health-services`, `frontend`, `core-services` (dev only) | ✓ | ✓ | ✓ |
| `studio` | `studio` | `studio-services` | ✓ | ✓ | ✓ |
| `urban` | `urban` | `urban`, `common-services`, `core-services` (dev only) | ✓ | ✓ | – |
| `care` | `care` | `care` | ✓ | – | – |
| `backbone` | `backbone`, `clickhouse`, `airflow`, `security`, `playground` | `backbone-services` | ✓ | ✓ | ✓ |
| `monitoring` | `monitoring` | upstream Helm repos | ✓ | ✓ | ✓ |
| `kargo` | `unified-core`, `unified-health`, `unified-studio` | `kargo` | ✓ | – | – |

Not every domain exists in every environment, and the same domain can differ
between them — `health` pulls from `core-services` in dev but not in qa or uat.
**Check `charts/argo-cd/<env>/<domain>/` before assuming.**

Two domains do not follow the appset pattern:

- **`monitoring`** is a set of hand-written Applications in
  `monitoring-applications.yaml`, each pulling an upstream chart (Prometheus,
  Grafana, Loki…) with local values overlays. Adding one means adding an
  Application, not a list element.
- **`kargo`** manages promotion pipelines rather than deployed services. See
  `docs/kargo/`.

---

## 4. Add a service to an existing namespace

The common case. Two steps.

### 4.1 Make sure the chart exists

Your service needs a Helm chart in the matching family, e.g.
`charts/health-services/my-service/`. Copy a neighbouring service and adjust.

Most charts here are thin wrappers over the shared `common` library:

```yaml
# charts/health-services/my-service/templates/deployment.yaml
{{- template "common.deployment" . -}}
```

with everything driven from `values.yaml`.

> **Gotcha:** in these charts `resources`, `env`, `initContainers` and
> `extraVolumes` are **strings**, not maps — the `common` chart runs them
> through `tpl`. Use a `|` block:
> ```yaml
> resources: |
>   requests:
>     cpu: 100m
>     memory: 256Mi
> ```
> A map here fails to render with `expected map, got &{}`.

### 4.2 Add one element to the ApplicationSet

Pick the appset whose `path` matches your chart family:

```yaml
# charts/argo-cd/unified-dev/health/health-app-set-health.yaml
  generators:
    - list:
        elements:
          - name: existing-service
          - name: my-service        # <- add this
```

That is the whole deployment. On push, the appset generates an Application
named `health-my-service`, which renders
`charts/health-services/my-service` with
`values.yaml` + `environments/unified-health-dev.yaml`.

> Some appsets (notably `backbone`) also require `namespace:` on each element,
> because their template substitutes `{{namespace}}`. Follow whatever the
> neighbouring elements do — a missing key renders the literal string
> `{{namespace}}` and the sync fails.

**Promoting to QA and UAT** is the same edit in
`charts/argo-cd/unified-qa/...` and `charts/argo-cd/unified-uat/...`. Nothing
propagates automatically — that is deliberate.

---

## 5. Deploy into a new namespace

Four extra steps, because three separate things must agree on the namespace:
cluster-configs creates it, the AppProject permits it, and the appset targets
it.

### 5.1 Create the namespace

Namespaces come from `cluster-configs`, not from Argo CD's
`CreateNamespace` — that way they are created with the right labels.

Add it to the environment file whose `cluster-configs` Application covers your
domain:

```yaml
# environments/unified-<domain>-<env>.yaml   (e.g. unified-health-dev.yaml)
cluster-configs:
  namespaces:
    create: true
    values: [ health, sso, my-namespace ]      # <- add here
```

Each domain has its own `cluster-configs` Application
(`cluster-configs-unified-health-dev`, `-studio-dev`, `-urban-dev`, …), each
reading its own environment file. Add the namespace to the one that matches
your domain, not to `unified-dev.yaml`, unless yours is a platform-wide
namespace.

### 5.2 Allow the namespace in the AppProject

An AppProject lists exactly which namespaces its Applications may write to. A
namespace that is not listed is rejected at sync:

```yaml
# charts/argo-cd/<env>/<domain>/<domain>-app-project.yaml
  destinations:
    - namespace: 'health'
      server: https://kubernetes.default.svc
    - namespace: 'my-namespace'               # <- add this
      server: https://kubernetes.default.svc
```

If your service installs **cluster-scoped** objects (CRDs, ClusterRole,
webhooks), those kinds must also be in `clusterResourceWhitelist`. Most
application services need nothing here.

If it pulls a chart from **outside this repo** (an upstream Helm repo), add
that repo to `sourceRepos` as well — see §8.

### 5.3 Point an appset at it

Either add your service to an existing appset whose `destination.namespace`
is already your namespace, or create a new appset file in the domain
directory. Copy a neighbouring one and change `path`,
`destination.namespace` and the element list.

### 5.4 Image pull credentials

Images come from a private Docker Hub org, so each namespace needs a
`docker-registry-secret`. A brand-new namespace will not have one, and pods
will sit in `ImagePullBackOff`. Ask DevOps to seed it.

---

## 6. Configuration and secrets

### 6.1 Non-sensitive configuration

Per-service configuration goes in the environment file, keyed by **chart
name**:

```yaml
# environments/unified-health-dev.yaml
my-service:
  replicas: 2
  images:
    - egovio/my-service:master-abc1234
  java-args: -Xmx512m -Xms256m
```

The `common` library merges `.Values.<chart-name>` over the chart's own
`values.yaml`, with the environment winning. That is why the top-level key must
match the chart directory name exactly.

> **Lists are replaced, not merged.** Overriding one entry of a list in the
> environment file replaces the whole list. State the complete list.

### 6.2 Secrets

Secrets are **SOPS-encrypted** and rendered by `cluster-configs` — never put a
plaintext credential in a values file or a chart.

1. Add a template under
   `charts/cluster-configs/templates/secrets/<name>-secret.yaml`
2. Declare the non-sensitive parts (secret name, namespaces) in
   `charts/cluster-configs/values.yaml`
3. Put the credentials in `environments/unified-<domain>-<env>-secrets.yaml`,
   which is SOPS-encrypted and needs someone with decrypt rights

Then reference the secret from your chart with `secretKeyRef` / `envFrom`.

> Editing a live Secret with `kubectl` is pointless — Argo CD's `selfHeal`
> reverts it on the next pass. Change it in SOPS and push.

> Avoid `@ : / ? # & % ' " \` and spaces in generated passwords. Each of them
> breaks a Postgres URI, a JDBC string or shell quoting somewhere in this
> stack.

---

## 7. Verify your deployment

You do not need cluster access to deploy, but you do to verify. If you do not
have it, ask DevOps to run these.

```bash
# 1. did the appset generate your Application?
kubectl -n argocd get app | grep my-service

# 2. is it synced and healthy?
kubectl -n argocd get app <domain>-my-service

# 3. is it actually running?
kubectl -n <namespace> get pods -l app=my-service
kubectl -n <namespace> logs deploy/my-service --tail=50
```

Render the chart locally first — it catches most mistakes before you push:

```bash
cd deploy-as-code/helm
helm template my-service charts/health-services/my-service \
  -f charts/health-services/my-service/values.yaml \
  -f environments/unified-health-dev.yaml
```

---

## 8. When something does not work

| Symptom | Cause |
|---|---|
| No Application appears at all | Element not added, added to the wrong env directory, or pushed to the wrong branch |
| `Unknown` / `Unknown`, never syncs | The chart's source repo is not in the AppProject's `sourceRepos`. A rejected spec never reaches a sync attempt — this does **not** show as `OutOfSync` |
| `application destination ... is not permitted` | Namespace missing from the AppProject's `destinations` (§5.2) |
| `app path does not exist` | The chart directory is not committed, or `path` does not match the chart family |
| `resources: expected map, got &{}` | `resources` written as a map instead of a `|` string (§4.1) |
| Pods in `ImagePullBackOff` | Missing `docker-registry-secret` in the namespace (§5.4), or the tag does not exist |
| `CreateContainerConfigError` | A referenced Secret or ConfigMap key does not exist yet |
| Application permanently `OutOfSync` while Healthy | A controller writes defaults back onto the object. Usually needs `ServerSideDiff=true` on the Application, not an `ignoreDifferences` list |
| Config change has no effect | Top-level key in the environment file does not match the chart directory name (§6.1) |
| Argo CD shows an old revision | Force a refresh: `kubectl -n argocd annotate app <name> argocd.argoproj.io/refresh=hard --overwrite` |

---

## 9. Checklists

### Existing namespace

- [ ] Chart exists under the right family and is committed
- [ ] `resources`/`env` are `|` strings, not maps
- [ ] Element added to the appset for the right environment
- [ ] `namespace:` included on the element, if its neighbours have it
- [ ] Config added to `environments/<env>.yaml` under the chart name
- [ ] Secrets added via SOPS + cluster-configs, not inline
- [ ] `helm template` renders locally
- [ ] PR against `unified-env-lts`

### New namespace — everything above, plus

- [ ] Namespace added to the right domain's `cluster-configs.namespaces.values`
- [ ] Namespace added to the AppProject's `destinations`
- [ ] Cluster-scoped kinds added to `clusterResourceWhitelist`, if any
- [ ] External chart repos added to `sourceRepos`, if any
- [ ] `docker-registry-secret` seeded in the new namespace

---

## Related

- `charts/backbone-services/postgresql-18/README.md` — a worked example of
  adding a service that needs an operator, a new namespace, SOPS credentials
  and `ServerSideDiff`
- `docs/kargo/` — promoting builds between dev, QA and UAT once deployed
