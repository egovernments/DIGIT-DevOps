# DIGIT 3.0 on unified-dev (`digit-3.0`)

All Argo CD config for the DIGIT 3.0 module. Two sub-areas, by namespace:

| Sub-area | Namespace | Holds | Deployed by |
|---|---|---|---|
| **core-3.0** | `core-3-0` | core services, kong, keycloak, cluster-configs | Kargo project `digit-3-0` -> kargo-managed ApplicationSets |
| **backbone-3.0** | `backbone-3-0` | postgresql-18, vault | `backbone-3.0/` here (postgres, git-path) + Kargo (vault) |

(Namespaces are dot-free because a Kubernetes namespace cannot contain `.`; the folders and env files keep the dotted `digit-3.0` / `core-3.0` / `backbone-3.0` names.)

- **`digit-3-0-app-project.yaml`** - the single AppProject for the whole module (destinations `core-3-0` + `backbone-3-0`). One project, not one per sub-area, because `cluster-configs` renders into both namespaces.
- **`backbone-3.0/postgresql-18-application.yaml`** - the module's CloudNativePG database (coredb + keycloak), dedicated to DIGIT 3.0. Needs the cluster-wide `cloudnative-pg-operator` Application.
- **core services** have no static files here: they are generated from the Kargo project config (`charts/kargo/config/projects/digit-3-0.yaml`) by the kargo-managed ApplicationSets after each promotion.

Env overrides for everything above live in `deploy-as-code/helm/environments/digit-3.0/core-3.0.yaml` (+ `core-3.0-secrets.yaml`, SOPS).
