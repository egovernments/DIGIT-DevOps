# Repository Layout and Conventions

<sub>**Deployment Guide** · Part 3 of 11 · [Contents](README.md) · Next: [Kargo Guide](04-kargo-guide.md)</sub>

## Branches

| Branch | Describes | Written by |
|---|---|---|
| `<dev-branch>` | The dev cluster | Pull requests; Kargo promotions to dev |
| `<qa-branch>` | The qa cluster | Pull requests; Kargo promotions to qa |
| `<uat-branch>` | The uat cluster | Pull requests; Kargo promotions to uat |

- Every environment branch is **protected**: changes arrive by reviewed pull request, or by a Kargo promotion commit (`kargo: promote <service> to <env>`).
- A cluster's Argo CD reads **only its own branch**. A change reaches an environment only when it lands on that branch.
- Kargo project configs live on the branch Kargo's cluster reads (`<config-branch>`, usually the dev branch).

## Folder structure

```
<repo>/
├── <argocd-dir>/
│   ├── bootstrap/
│   │   └── <env>-bootstrap.yaml              # applied once per cluster, by hand
│   └── <env>/                                # synced recursively by the bootstrap app
│       ├── <module>/
│       │   ├── <module>-app-project.yaml     # AppProject: repos + namespaces allowed
│       │   ├── <module>-app-set.yaml         # ApplicationSet (Argo CD only model)
│       │   └── <module>-config-application.yaml
│       ├── kargo-managed/                    # (Kargo) shared layout ApplicationSets
│       │   ├── kargo-managed-app-set-common.yaml
│       │   ├── kargo-managed-app-set-root.yaml
│       │   └── kargo-managed-app-set-configs.yaml
│       └── kargo/                            # (Kargo) control plane + pipelines ApplicationSet
├── <kargo-pipeline-chart-path>/              # (Kargo) pipeline chart
│   └── config/projects/<project>.yaml        # one project config per module
├── <environments-dir>/
│   ├── <module>-<env>.yaml                   # values + pinned versions
│   └── <module>-<env>-secrets.yaml           # SOPS-encrypted
└── .sops.yaml                                # which key encrypts which secrets file
```

## Naming

| Object | Convention | Example |
|---|---|---|
| Env file | `<module>-<env>.yaml` | `payments-dev.yaml` |
| Secrets file | `<module>-<env>-secrets.yaml` | `payments-dev-secrets.yaml` |
| AppProject | `<module>-project` | `payments-project` |
| ApplicationSet | `<env>-<module>-appset[-<group>]` | `dev-payments-appset` |
| Application | `<app-prefix><service>` | `payments-invoice-service` |
| Kargo project | `<project>` (no dots: it is a namespace) | `payments` |
| Kargo Warehouse | `<service>` | `invoice-service` |
| Kargo Stage | `<service>-<env>` | `invoice-service-qa` |
| Image | `<registry>/<service>`, migration image `<registry>/<service>-db` | `docker.io/acme/invoice-service` |
| Chart | `<service>` in `https://helm.digit.org` | `invoice-service` |

`<app-prefix>` must be unique across modules, so Application names never collide.

## The env file

One env file per module per environment. Structure (template: [templates/environments/module-env.yaml](templates/environments/module-env.yaml)):

```yaml
global:                      # read by every service of the module
  namespace: <namespace>
  domain: <domain>
  mode: dev                  # image-tag mode of the shared library chart, if it has one

cluster-configs:             # module ConfigMaps and Secret declarations (config Application)
  namespaces: { create: false, values: [<namespace>] }
  configmaps: { … }
  secrets: { … }

<service>:                   # one section per service, keyed by CHART NAME
  replicas: 1
  ingress: { enabled: true }
  chart-version: '<x.y.z>'   # Kargo-owned
  image:
    tag: '<tag>'             # Kargo-owned
```

Rules:

- **Sections are keyed by chart name.** The library chart merges `.Values.<chart-name>`; any other key is ignored silently.
- **Kargo-owned keys** (`chart-version`, `image.tag`, `initContainers.dbMigration.image.tag`) are written only by promotions, or by pull request in the Argo CD only model.
- **Lists are replaced, not merged.** When overriding a list from the chart defaults, restate every item.
- **No secrets.** Values that must be secret go in the secrets file.
- **One module per file.** Never put one module's services in another module's env file.

## Commit messages

| Change | Message |
|---|---|
| Kargo promotion | `kargo: promote <service> to <env>` (generated) |
| Pull requests | `<type>(<scope>): <summary>`, for example `feat(payments): onboard invoice-service` |

---

<sub>← Previous: [Prerequisites and Installation](02-prerequisites-and-installation.md) &nbsp;|&nbsp; [Contents](README.md) &nbsp;|&nbsp; Next: [Kargo Guide](04-kargo-guide.md) →</sub>
