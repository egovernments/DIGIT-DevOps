# Kargo-managed Applications on unified-dev

Applications for services promoted by Kargo are generated from the **Kargo project
config** (`charts/kargo/config/projects/<project>.yaml`). A service is declared once,
there, and appears in Argo CD after its first promotion. No ApplicationSet edit is
needed per service.

Today only `digit-core3-0` opts in. Projects without a `kargo.argocd` block are
ignored here and keep their own ApplicationSets (egov, health, studio, ...).

## How it works

Each ApplicationSet here is a matrix over:

1. every Kargo project config with `kargo.argocd.project` set;
2. that project's env file for this cluster's stage (`dev`): `envFile` and `branch`
   of the `dev` stage in the same config;
3. one element per service whose layout matches the ApplicationSet and whose
   `<valuesKey>.chart-version` exists in the env file (Kargo merges it on the first
   promotion).

| Application field | Comes from |
|---|---|
| name | `deploy.app`, else `argocdAppPrefix` + service name |
| project | `kargo.argocd.project` |
| namespace | `deploy.namespace`, else `kargo.argocd.namespace` |
| chart | `chartRepo` (service, else project) / `chart` at `<valuesKey>.chart-version` |
| release name | `deploy.releaseName`, else the service name |

## Layouts: one ApplicationSet each

The layout is how a chart takes its values: `deploy.layout`, else `kargo.argocd.layout`.

| Layout | File | Values |
|---|---|---|
| `common` | `kargo-managed-app-set-common.yaml` | `{global, <valuesKey>}` from the env file (DIGIT common chart) |
| `root` | `kargo-managed-app-set-root.yaml` | the `<valuesKey>` section minus `chart-version`, as root values; CRDs skipped |
| `configs` | `kargo-managed-app-set-configs.yaml` | the env file and `<env file>-secrets.yaml` from git (cluster-configs chart) |

Services in the same layout share an ApplicationSet whatever their namespace. A new
ApplicationSet is only needed for a chart that takes values in a way none of these do.

## Add a service

Add it to the project's Kargo config (most services need no `deploy`), then promote:

```yaml
    - name: my-service          # layout common, namespace kargo.argocd.namespace
      chart: my-service
    - name: my-gateway
      chart: my-gateway
      deploy:
        layout: root
        namespace: vault        # must be in kargo.argocd.namespaces
```

The Kargo chart (`templates/argocd-deploy.yaml`) fails that project's render for an
unknown layout or a namespace outside `kargo.argocd.namespaces`.

## Add a project

1. Kargo config with a `kargo.argocd` block (`project`, `namespace`, `namespaces`,
   `layout`), and its element in `../kargo/kargo-app-set-pipelines.yaml`.
2. The env file named by its `dev` stage.
3. An AppProject in `../<module>/<module>-app-project.yaml` whose destinations match
   `kargo.argocd.namespaces`. It stays hand-written: it is what limits where the
   project can deploy.

App names must stay unique across projects: give each project its own `argocdAppPrefix`.
