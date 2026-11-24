# Kargo-managed Applications on unified-dev

Applications for services promoted by Kargo are generated from the **Kargo project
config** (`charts/kargo/config/projects/<project>.yaml`). A service is declared once,
there, and appears in Argo CD after its first promotion. No ApplicationSet edit is
needed per service.

`digit-3-0` and `unified-security` opt in. Projects without a `kargo.argocd`
block are ignored here and keep their own ApplicationSets (egov, health,
studio, ...).

## How it works

Each ApplicationSet here is a matrix over:

1. every Kargo project config with `kargo.argocd.project` set;
2. that project's env file for this cluster's stage (`dev`): `envFile` and `branch`
   of the `dev` stage in the same config;
3. one element per service whose layout matches the ApplicationSet and whose
   `<valuesKey>.chart-version` exists in the env file (Kargo writes it on the first
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
| `cluster` | `kargo-managed-app-set-cluster.yaml` | as `root`, but CRDs are installed and the namespace is created on sync |

`cluster` is for an add-on that installs cluster-scoped objects (kubescape). The
other three layouts set `skipCrds: true`, which leaves such a chart permanently
degraded when something in it depends on its own CRD -- kubescape's aggregated
APIService is backed by one. **Choosing it is a privilege decision:** the
project's AppProject must carry a `clusterResourceWhitelist` naming every
cluster-scoped kind the chart renders, listed explicitly and never `'*'`, so a
chart version that starts creating something new fails the sync loudly instead
of quietly gaining privilege.

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
2. The env file named by its `dev` stage -- normally the cluster-wide
   `environments/unified-<env>.yaml`, with the project under its own top-level
   key; a project needs a file of its own only if it deploys somewhere that
   file does not describe.
3. An AppProject in `../<module>/<module>-app-project.yaml` whose destinations match
   `kargo.argocd.namespaces`. It stays hand-written: it is what limits where the
   project can deploy.
4. **The project's own namespace added to `kargo-project`'s destinations** in
   `../kargo/kargo-app-project.yaml`. Kargo's `Project` resource creates that
   namespace, and the Application that applies the pipeline is itself in
   `kargo-project` -- so without this the pipeline Application never syncs. It
   fails as `InvalidSpecError`, not a sync error, so it shows up in Argo CD as
   `Unknown`/`Unknown` with nothing in its operation state:

   ```
   application destination server 'https://kubernetes.default.svc' and namespace
   '<project>' do not match any of the allowed destinations in project 'kargo-project'
   ```

5. **The project's namespace added to `cluster-configs`' kargo project list**
   (`charts/cluster-configs/values.yaml`, `secrets.kargo.projects`). That is
   what renders `git-creds-*`, `image-creds-*` and `verify-kubeconfig-*` into
   the namespace. Without it the Warehouse cannot authenticate to the registry
   and promotion fails at `git-push`:

   ```
   fatal: could not read Username for 'https://github.com': No such device or address
   ```

App names must stay unique across projects: give each project its own `argocdAppPrefix`.
