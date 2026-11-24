# DIGIT 3.0 on unified-dev (`digit-3.0`)

All Argo CD config for DIGIT 3.0, grouped per module. Each module is its own Kargo project;
all of them use published charts from `helm.digit.org`.

```
digit-3.0/
  core-3.0/        core module       -> namespace core-3-0
  backbone-3.0/    shared backbone   -> namespace backbone-3-0
  health-3.0/      (soon)            -> namespace health-3-0
```

| Folder | Namespace | Holds | Deployed by |
|---|---|---|---|
| **core-3.0** | `core-3-0` | core services, kong, keycloak, cluster-configs | Kargo project `core-3-0` -> kargo-managed ApplicationSets |
| **backbone-3.0** | `backbone-3-0` | postgresql-18, vault | Kargo project `backbone-3-0` -> kargo-managed ApplicationSets |
| **health-3.0** | `health-3-0` | health services (soon) | Kargo project `health-3-0` (to be onboarded) |

(Namespaces are dot-free because a Kubernetes namespace cannot contain `.`; the folders and
env files keep the dotted `core-3.0` / `backbone-3.0` / `health-3.0` names.)

## Projects and ownership

- **`core-3.0/core-3-0-app-project.yaml`** - AppProject `core-3-0-project`, destinations
  `core-3-0` **and** `backbone-3-0`. It spans backbone-3-0 for one reason: the postgresql-18
  credential Secrets are SOPS-encrypted and so must be rendered by the SOPS-enabled
  `core-3-0-cluster-configs` Application (a core app), which pins them into `backbone-3-0`.
- **`backbone-3.0/backbone-3-0-app-project.yaml`** - AppProject `backbone-3-0-project`,
  destination `backbone-3-0` only. Hosts the `digit3-postgresql-18` and `digit3-vault`
  Applications (the postgres Cluster + vault workloads).
- A **Kargo project is a namespace**, so each project's pipeline (Warehouses/Stages) and its
  workloads share the one namespace: `core-3-0` for core, `backbone-3-0` for backbone.

## Backbone (published charts, chart-only)

postgresql and vault are **chart-only** services (`image: false`) of the `backbone-3-0` Kargo
project (`charts/kargo/config/projects/backbone-3-0.yaml`), installed by the kargo-managed
root ApplicationSet from the published charts at `helm.digit.org/digit3/backbone`. They are not
routinely promoted; the chart versions are pinned and move only on a deliberate upgrade. The
backbone-3.0 folder holds only the AppProject - the Applications are appset-generated.

- **`digit3-postgresql-18`** - chart `postgresql` (CloudNativePG). `coredb` owned by `coredev`,
  bootstrapped via `cluster.initdb` from the `postgresql-18-db` secret; postgis supplied as an
  image volume (`cluster.postgresql.extensions`, needs chart >= 3.0.3). The post-ready reconciler
  is disabled, so nothing is created outside `backbone-3-0`. Needs the cluster-wide
  `cloudnative-pg-operator` Application.
- **`digit3-vault`** - chart `vault` with Raft + Azure Key Vault auto-unseal (Workload Identity;
  client-id `SET-AT-CUTOVER`, DIGIT-DevOps#5762). Agent injector + CSI disabled (services use
  AppRole), auth-delegator off, so it renders nothing cluster-scoped.

Root layout: the appset passes each service's env-file section (minus `chart-version`) as the
chart's ROOT values, so the published charts read their plain values - no re-rooting.

## core services

Core services have no static files here: they are generated from the Kargo project config
(`charts/kargo/config/projects/core-3-0.yaml`) by the kargo-managed ApplicationSets after each
promotion.

## Env overrides

Everything above (core **and** backbone) reads
`deploy-as-code/helm/environments/digit-3.0/core-3.0.yaml` (+ `core-3.0-secrets.yaml`, SOPS).
