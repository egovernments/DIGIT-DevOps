# DIGIT 3.0 on unified-dev (`digit-3.0`)

All Argo CD config for DIGIT 3.0, grouped per module. Each promotable module is its own
Kargo project; the backbone is shared, non-promotable infra.

```
digit-3.0/
  core-3.0/        core module       -> namespace core-3-0
  backbone-3.0/    shared infra      -> namespace backbone-3-0
  health-3.0/      (soon)            -> namespace health-3-0
```

| Folder | Namespace | Holds | Deployed by |
|---|---|---|---|
| **core-3.0** | `core-3-0` | core services, kong, keycloak, cluster-configs | Kargo project `core-3-0` -> kargo-managed ApplicationSets |
| **backbone-3.0** | `backbone-3-0` | postgresql-18, vault | static git-path Applications here (not Kargo) |
| **health-3.0** | `health-3-0` | health services (soon) | Kargo project `health-3-0` (to be onboarded) |

(Namespaces are dot-free because a Kubernetes namespace cannot contain `.`; the folders and
env files keep the dotted `core-3.0` / `backbone-3.0` / `health-3.0` names.)

## Projects and ownership

- **`core-3.0/core-3-0-app-project.yaml`** - AppProject `core-3-0-project`, destinations
  `core-3-0` **and** `backbone-3-0`. It spans backbone-3-0 for one reason: the postgresql-18
  credential Secrets are SOPS-encrypted and so must be rendered by the SOPS-enabled
  `core-3-0-cluster-configs` Application (a core app), which pins them into `backbone-3-0`.
- **`backbone-3.0/backbone-3-0-app-project.yaml`** - AppProject `backbone-3-0-project`,
  destination `backbone-3-0` only. Owns the postgres Cluster and vault workloads.
- A **Kargo project is a namespace**, so the `core-3-0` pipeline (Warehouses/Stages) and the
  core workloads share namespace `core-3-0` (co-located). `backbone-3-0` has no Kargo project.

## Backbone is static (not promoted)

A database and a secrets engine are infra, not images promoted dev -> qa -> uat, so they are
plain git-path Applications shared by core-3.0 and health-3.0:

- **`backbone-3.0/postgresql-18-application.yaml`** - CloudNativePG (coredb + keycloak),
  dedicated to DIGIT 3.0. Needs the cluster-wide `cloudnative-pg-operator` Application.
- **`backbone-3.0/vault-application.yaml`** - vault with Raft + Azure Key Vault auto-unseal
  (Workload Identity; client-id `SET-AT-CUTOVER`, DIGIT-DevOps#5762). The chart
  (`charts/backbone-services/vault`) reads a nested `vault:` key, like postgresql-18, so its
  config lives in the module env file alongside core.

## core services

Core services have no static files here: they are generated from the Kargo project config
(`charts/kargo/config/projects/core-3-0.yaml`) by the kargo-managed ApplicationSets after each
promotion.

## Env overrides

Everything above (core **and** backbone) reads
`deploy-as-code/helm/environments/digit-3.0/core-3.0.yaml` (+ `core-3.0-secrets.yaml`, SOPS).
