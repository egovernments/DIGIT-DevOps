# Glossary

<sub>**Deployment Guide** · Part 11 of 11 · [Contents](README.md)</sub>

| Term | Definition |
|---|---|
| **AppProject** | Argo CD object limiting which repositories, namespaces and cluster-scoped kinds a group of Applications may use. One per module. |
| **Application** | Argo CD object deploying one chart (at one version, with one set of values) into one namespace. |
| **ApplicationSet** | Argo CD object generating Applications from a template and generators (lists, git files). |
| **Bootstrap Application** | The one Application applied by hand per cluster; it syncs all other Argo CD manifests for that environment. |
| **Chart version** | The version of a packaged chart in the Helm repository. Pinned per service per environment in the env file. |
| **Config Application** | The Application rendering a module's ConfigMaps and Secrets into its namespaces. |
| **Env file** | `<module>-<env>.yaml`: a module's values and pinned versions for one environment. |
| **Environment branch** | The git branch describing one environment's cluster. |
| **Freight** | Kargo's immutable release bundle: one image tag and one chart version for a service. |
| **Image-tag mode** | A library-chart setting deciding whether `image.tag` or the chart's `appVersion` sets the image. |
| **Kargo-managed Applications** | Applications generated from the Kargo project config by the shared layout ApplicationSets. |
| **Layout** | How an Application hands env-file values to a chart: `common`, `root` or `configs`. |
| **Mainline build** | A build of the main branch (`master-*` tags); the only builds accepted in uat. |
| **Module** | A group of services released and configured together; one env file and one AppProject per environment. |
| **Project (Kargo)** | A module's Kargo pipelines; a namespace on the Kargo cluster. |
| **Project config** | The values file from which a Kargo project's objects are rendered. |
| **Promotion** | Moving Freight into a Stage: writes the versions into the env file, commits and pushes. |
| **Prune** | Argo CD deleting objects that are no longer rendered. Off in this setup. |
| **Self-heal** | Argo CD reverting cluster drift to git. On in this setup. |
| **Server-side apply** | Kubernetes apply mode used for syncs; rejects objects with duplicate list keys (for example env names). |
| **SOPS** | Tool encrypting secret values in git with a cloud key (Azure Key Vault or AWS KMS). |
| **Stage** | Kargo object for one service in one environment; holds the Freight running there. |
| **Warehouse** | Kargo object discovering a service's images and chart versions. |

---

<sub>← Previous: [Troubleshooting](10-troubleshooting.md) &nbsp;|&nbsp; [Contents](README.md)</sub>
