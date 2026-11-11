# Argo CD

<sub>Stage 5 of 5 - [Workflows](<../1. Workflows/README.md>) -> [Code Build](<../2. Code Build/README.md>) -> [Helm Packaging & Releasing](<../3. Helm Packaging & Releasing/README.md>) -> [Kargo Promotions](<../4. Kargo Promotions/README.md>) -> **Argo CD**</sub>

Argo CD deploys whatever each environment's git branch describes. When a chart version and image tag change in an env file - written by a [Kargo promotion](<../4. Kargo Promotions/>) or by a pull request - Argo CD renders the chart at that version with those values and applies the difference to the cluster. The cluster is continuously reconciled back to git, so the branch is the single source of truth.

| If you want to | Read |
|---|---|
| Understand the model, bootstrap, and how an env file becomes a Deployment | [getting-started.md](getting-started.md) |
| Add a new application or a new module | [onboarding-a-service.md](onboarding-a-service.md) |
| Reach the UI and check or refresh a deployment | [access-and-use.md](access-and-use.md) |
| Manage secrets, sync policy, Argo CD itself, and fix sync problems | [maintenance.md](maintenance.md) |

## The model in four points

- **Git is the single source of truth.** Every object Argo CD manages is rendered from the environment branch.
- **Packaged charts.** Applications install `chart <service>` from `https://helm.digit.org` at the exact version pinned in the env file.
- **One env file per module.** Values and pinned versions for every service of the module.
- **Automated sync with self-heal.** Drift on the cluster is reverted; the cluster always matches git.
