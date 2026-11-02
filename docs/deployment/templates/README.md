# Templates

Ready-to-copy files for the approach described in this guide. Replace every `<placeholder>` (see the [placeholder table](../README.md#placeholders)). Comments in each file explain the choices it encodes.

## Argo CD

| File | Use it for | Model |
|---|---|---|
| [argocd/bootstrap-application.yaml](argocd/bootstrap-application.yaml) | The one Application applied by hand per cluster | Both |
| [argocd/appproject.yaml](argocd/appproject.yaml) | A module's AppProject (repositories, namespaces) | Both |
| [argocd/applicationset-argocd-only.yaml](argocd/applicationset-argocd-only.yaml) | A module's services, versions set by pull request | Argo CD only |
| [argocd/applicationset-kargo-managed-common.yaml](argocd/applicationset-kargo-managed-common.yaml) | Applications from Kargo configs, `common` layout | Kargo + Argo CD |
| [argocd/applicationset-kargo-managed-root.yaml](argocd/applicationset-kargo-managed-root.yaml) | Applications from Kargo configs, `root` layout | Kargo + Argo CD |
| [argocd/applicationset-kargo-managed-configs.yaml](argocd/applicationset-kargo-managed-configs.yaml) | Applications from Kargo configs, `configs` layout | Kargo + Argo CD |
| [argocd/config-application.yaml](argocd/config-application.yaml) | A module's ConfigMaps/Secrets Application | Both |
| [argocd/kargo-pipelines-applicationset.yaml](argocd/kargo-pipelines-applicationset.yaml) | Installs each Kargo project from its project config | Kargo + Argo CD |

## Kargo

| File | Use it for |
|---|---|
| [kargo/project-config.yaml](kargo/project-config.yaml) | A project config for the pipeline chart: services, stages, teams, Argo CD placement |
| [kargo/manifests/project.yaml](kargo/manifests/project.yaml) | Raw Project and ProjectConfig (manual promotion) |
| [kargo/manifests/warehouse.yaml](kargo/manifests/warehouse.yaml) | Raw Warehouse (image + chart subscriptions) |
| [kargo/manifests/stage-first.yaml](kargo/manifests/stage-first.yaml) | Raw first Stage (dev): writes the versions into the env file |
| [kargo/manifests/stage-downstream.yaml](kargo/manifests/stage-downstream.yaml) | Raw qa and uat Stages, including the mainline-only guard |
| [kargo/manifests/team-rbac.yaml](kargo/manifests/team-rbac.yaml) | Raw stage-scoped promotion access for an SSO team |

## Environments

| File | Use it for |
|---|---|
| [environments/module-env.yaml](environments/module-env.yaml) | A module env file: global, module configuration, service sections |
| [environments/module-env-secrets.example.yaml](environments/module-env-secrets.example.yaml) | The structure of a secrets file (encrypt before committing) |
| [environments/sops.yaml](environments/sops.yaml) | `.sops.yaml` rules for Azure Key Vault and AWS KMS |

## Access

| File | Use it for |
|---|---|
| [access/cluster-readonly-access.yaml](access/cluster-readonly-access.yaml) | Debugging access for a service team (no Secret read) |
| [access/database-readonly-role.sql](access/database-readonly-role.sql) | A read-only database login |
