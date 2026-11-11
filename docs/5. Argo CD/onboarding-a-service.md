# Argo CD - Onboard a New Application or Module

<sub>[Argo CD](README.md) - Onboarding</sub>

How an Application is generated decides how you onboard. There are two models; a cluster can use either, or both.

## How Applications are generated

### Kargo-managed (Kargo + Argo CD)

Shared ApplicationSets read each Kargo project config that has an `argocd:` block, then that project's env file. They create one Application per service **once its `chart-version` exists in the env file** (that is, after its first promotion). **Adding a service is one entry in the Kargo project config - no ApplicationSet change.**

```yaml
kargo:
  argocdAppPrefix: <app-prefix>
  argocd:
    project: <module>-project          # AppProject
    namespace: <namespace>             # default namespace
    namespaces: [<namespace>]          # must equal the AppProject destinations
    layout: common                     # default layout
  services:
    - name: <service>                  # -> Application <app-prefix><service>
      chart: <service>
    - name: <gateway-service>
      chart: <gateway-chart>
      deploy: { layout: root, namespace: <other-namespace> }
```

### Hand-listed (Argo CD only, no Kargo)

An ApplicationSet lists the services and reads the same env file; engineers set `chart-version` and `image.tag` by pull request. With `missingkey=error`, a listed service whose env file has no `chart-version` stops generation for the whole ApplicationSet. Add the element only when its version is in the env file, or guard the git generator with a selector:

```yaml
selector:
  matchExpressions:
    - key: <service>.chart-version
      operator: Exists
```

### Some environments deploy through existing ApplicationSets

A cluster can also be set up so the existing per-module ApplicationSets do the deploying, and Kargo only writes the versions into the env file. The ApplicationSets' git-file generator re-reads the file (about every 60s) and rolls the change out. In that hybrid, onboarding a service is: add it to the Kargo project config (versions) and ensure the existing ApplicationSet covers its env-file section.

## Values layouts

A **layout** is how an Application hands the env file's values to a chart. Each layout is one shared ApplicationSet.

| Layout | Values given to the chart | Typical charts |
|---|---|---|
| `common` | `{ global: <global>, <service>: <service section> }` | Service charts built on the shared library chart |
| `root` | The service section as root values, minus `chart-version`; CRDs skipped | Third-party-style charts (gateways, secret stores) |
| `configs` | The whole env file plus its `-secrets.yaml` twin, as value files from git | The module's configuration chart (ConfigMaps, Secrets) |

- Layout and namespace are independent: two services in one layout can deploy to different namespaces.
- New layouts are rare. Add one only for a chart none of the three can serve; it then serves every project.
- Several `root`-layout services share one module env file as **sections**, each handed its own section as root values. Do **not** create a value file per service and layer them on; one env file per environment, one section per service.

## Onboard an application

**Kargo + Argo CD**

1. Publish the chart; confirm matching image tags exist.
2. Add the service to the Kargo project config (see [Kargo onboarding](<../4. Kargo Promotions/onboarding-a-service.md>)); add `deploy:` only if it differs from the project defaults.
3. Add its values to the env files, in a section named after the chart.
4. New namespace? Add it to the AppProject `destinations` **and** `argocd.namespaces` in the same pull request.
5. Merge, assemble Freight, promote. Confirm `<app-prefix><service>` reaches Synced and Healthy.

**Argo CD only**

1. Publish the chart.
2. In the env file, add the service section with `chart-version`, `image.tag` (and the migration tag) and its values.
3. Add the list element to the module ApplicationSet, or rely on the selector.
4. Namespace changes as above.
5. Merge; confirm Synced and Healthy. Later releases are pull requests changing the version keys, one environment branch at a time.

## Onboard a module

1. **Env files** per environment (`global`, `cluster-configs`, service sections) - template at [`../templates/environments/module-env.yaml`](../Templates/environments/module-env.yaml).
2. **Secrets:** a `.sops.yaml` rule, then the encrypted `-secrets.yaml` (see [maintenance.md](maintenance.md#secrets-and-sops)).
3. **AppProject** with the git and Helm repositories and the module's namespaces - template at [`../templates/argocd/appproject.yaml`](../Templates/argocd/appproject.yaml).
4. **Applications:** the `argocd:` block in the Kargo config (Kargo + Argo CD), or the module ApplicationSet plus a config Application (Argo CD only) - [`../templates/argocd/config-application.yaml`](../Templates/argocd/config-application.yaml).
5. **Namespace ownership:** exactly one Application owns each Namespace object.
6. **Order:** the AppProject must exist before an ApplicationSet that uses it is first reconciled. If an ApplicationSet reports its project does not exist, refresh it once the AppProject is there.

## Before raising either pull request

- Render the chart with the env file and read the output.
- Look for duplicate env var names.
- Confirm every referenced ConfigMap / Secret key exists. A published chart can reference `cluster-configs` keys that are not in the env file yet; a missing key surfaces only at runtime as `CreateContainerConfigError`, not in a render.
- Confirm the Ingress path is free.
