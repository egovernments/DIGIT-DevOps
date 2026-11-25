# DIGIT 3.0 structure: every file and what it does

This page is the map. It lists exactly which files make up DIGIT 3.0 on the unified
environments, what each one is for, and the small number of places you ever touch. All paths are
relative to the repository root. The DIGIT 3.0 work lives under
`deploy-as-code/helm/` (shortened to `.../helm/` below).

## The three kinds of files you edit (and nothing else)

Everything about DIGIT 3.0 is one of these three kinds of text. There is no fourth kind.

1. **Kargo pipeline config** - "which versions exist and how they promote."
2. **Argo CD project config** - "which repos and namespaces a module is allowed to use."
3. **Per-module values files** - "every setting for the module."

If a task seems to need a fourth kind (editing a chart template, writing an Application by hand),
re-read [Golden rules](README.md#golden-rules-do-not-break-these) - it does not.

## Directory map

```
deploy-as-code/helm/
├── charts/
│   ├── kargo/
│   │   ├── config/projects/
│   │   │   ├── core-3-0.yaml              # Kargo pipeline for the core module
│   │   │   ├── backbone-3-0.yaml          # Kargo pipeline for the backbone module
│   │   │   └── <module>-3-0.yaml          # one per module you add
│   │   ├── values.yaml                     # shared Kargo defaults (rarely touched)
│   │   └── templates/                      # Kargo chart templates (DO NOT edit to onboard)
│   │
│   └── argo-cd/unified-dev/
│       ├── kargo/
│       │   ├── kargo-app-set-pipelines.yaml   # the list of Kargo projects (register here)
│       │   └── kargo-app-project.yaml          # namespaces Kargo is allowed to manage
│       ├── kargo-managed/
│       │   ├── kargo-managed-app-set-common.yaml   # generates "common" layout services
│       │   ├── kargo-managed-app-set-root.yaml     # generates "root" layout services
│       │   ├── kargo-managed-app-set-configs.yaml  # generates cluster-configs
│       │   └── kargo-managed-app-set-cluster.yaml  # generates cluster-scoped apps
│       └── digit-3.0/
│           ├── README.md
│           ├── core-3.0/core-3-0-app-project.yaml       # AppProject for core
│           ├── backbone-3.0/backbone-3-0-app-project.yaml  # AppProject for backbone
│           └── <module>-3.0/<module>-3-0-app-project.yaml  # one per module you add
│
└── environments/
    ├── digit-3.0/
    │   ├── core-3.0.yaml                   # all core + backbone settings (shared)
    │   ├── core-3.0-secrets.yaml           # core/backbone secrets (SOPS-encrypted)
    │   ├── <module>-3.0.yaml               # one per module you add
    │   └── <module>-3.0-secrets.yaml       # one per module you add (SOPS)
    └── unified-dev.yaml                     # cluster-wide: namespace list + Kargo project list
```

## What each file is for

### Kargo project file - `charts/kargo/config/projects/<module>-3-0.yaml`

The heart of a module. It declares:

- `kargo.project` - the Kargo project name = the namespace (dashed, e.g. `core-3-0`).
- `kargo.argocd` - the Argo CD side: the AppProject name, the default namespace, the list of
  allowed namespaces, and the default layout.
- `kargo.chartRepo` - the published Helm repo for this module
  (`https://helm.digit.org/digit3/<module>`).
- `kargo.services` - the list of services. **Adding a service means adding an entry here.**
  Each entry says its chart name, whether it has a database migration image (`dbMigration`), and
  optionally a non-default `deploy.layout`, `deploy.namespace`, or `deploy.app`.
- `kargo.stages` - dev, qa, uat: which git branch each uses and which values file it writes to
  (always the module's own `environments/digit-3.0/<module>-3.0.yaml`).

`core-3-0.yaml` is heavily commented and is the best worked example to copy from.

### Kargo registration - `charts/argo-cd/unified-dev/kargo/kargo-app-set-pipelines.yaml`

A list with one element per Kargo project. Argo CD reads
`config/projects/<name>.yaml` for each element and creates that project. **A Kargo project file
does nothing until its name is added to this list.**

### Kargo namespace guardrail - `charts/argo-cd/unified-dev/kargo/kargo-app-project.yaml`

Lists the namespaces Kargo is allowed to operate in. A new module's namespace must be added here.

### kargo-managed ApplicationSets - `charts/argo-cd/unified-dev/kargo-managed/*.yaml`

These turn each service in a Kargo project file into an Argo CD Application
(`digit3-<service>`). There is one ApplicationSet per **layout**. **You never edit these per
service** - they read the Kargo project file. The layouts:

- **common** - for a standard DIGIT service. The chart receives `{global, <service>}` from the
  values file. Most services use this.
- **root** - the chart receives the service's whole values section (minus `chart-version`) as its
  top-level values. Used for third-party-style charts that expect plain values (kong, vault,
  postgresql).
- **configs** - for the `cluster-configs` chart; it receives the values file plus the encrypted
  secrets file and renders the module's ConfigMaps and Secrets.
- **cluster** - for the rare chart that installs cluster-scoped objects.

### Argo CD AppProject - `charts/argo-cd/unified-dev/digit-3.0/<module>-3.0/<module>-3-0-app-project.yaml`

A guardrail for the whole module. It lists:

- `sourceRepos` - the only repositories the module's apps may pull from (this git repo for
  values, and the module's published chart repos).
- `destinations` - the only namespaces the module may deploy into.

Anything a chart tries to render outside these namespaces is refused, so one module can never
overwrite another module's objects. No cluster-scoped kinds are whitelisted by default.

### Per-module values file - `environments/digit-3.0/<module>-3.0.yaml`

Every setting for the module. Structure:

```yaml
global:
  namespace: <module>-3-0                 # the dashed namespace
  mode: prod                               # prod = use the released image baked into each chart
  domain: <product>-3.unified-dev.digit.org   # the public hostname for this module
<service-a>:
  chart-version: "3.1.4"                   # which published chart version to install
  ingress:
    enabled: true
  # ... the service's settings ...
<service-b>:
  chart-version: "3.1.5"
  # ...
cluster-configs:
  chart-version: "3.1.0"
  # which ConfigMaps/Secrets to render and into which namespaces
```

Notes:
- `chart-version` for a service is normally filled in by the first Kargo promotion (it is
  merged in, not hand-seeded). You may seed it by hand to bootstrap before the first promotion.
- The backbone module (postgresql, vault) shares `core-3.0.yaml` today. A brand-new product gets
  its own `<module>-3.0.yaml`.

### Per-module secrets file - `environments/digit-3.0/<module>-3.0-secrets.yaml`

The same shape as the values file but only for secret values, encrypted with SOPS. It is matched
by a rule in the repository's `.sops.yaml` so the right key is used automatically. Never commit a
plaintext secret; always edit through SOPS so it is re-encrypted on save.

### Cluster registration - `environments/unified-dev.yaml`

The only two module entries that live here (everything else is in the module's own file):

1. The module namespace is added to the cluster-configs **namespaces** list (so the namespace is
   created and labelled for Kargo to adopt).
2. The Kargo **projects** list gets the module's project name.

## How a running service traces back to these files

```
helm.digit.org/digit3/<module>/<service>  (the published chart + its released image)
        |
        | referenced by name + chart-version
        v
charts/kargo/config/projects/<module>-3-0.yaml   (service listed here)
        |
        | a promotion writes chart-version + image.tag into...
        v
environments/digit-3.0/<module>-3.0.yaml   (the live settings)
        |
        | the kargo-managed ApplicationSet builds...
        v
Argo CD Application  digit3-<service>   (installs the chart with those values)
        |
        v
running pods in namespace <module>-3-0
```

Every arrow is text you can read in this repository. Nothing is hidden.
