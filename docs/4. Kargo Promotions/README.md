# Kargo Promotions

<sub>Stage 4 of 5 - [Workflows](<../1. Workflows/README.md>) -> [Code Build](<../2. Code Build/README.md>) -> [Helm Packaging & Releasing](<../3. Helm Packaging & Releasing/README.md>) -> **Kargo Promotions** -> [Argo CD](<../5. Argo CD/README.md>)</sub>

Kargo takes a built image and a published chart, pins them together as an immutable release (**Freight**), and promotes that release into an environment by writing the versions into the environment's git branch. Argo CD then deploys what git now says. Kargo never talks to the cluster workloads directly - it only moves versions through git.

Use this section once a service already has images in the registry (see [Code Build](<../2. Code Build/>)) and a chart published to the Helm repository (see [Helm Packaging & Releasing](<../3. Helm Packaging & Releasing/>)).

| If you want to | Read |
|---|---|
| Understand the model and find the control plane | [getting-started.md](getting-started.md) |
| Add a new service or a new project to a pipeline | [onboarding-a-service.md](onboarding-a-service.md) |
| Log in, assemble Freight, and promote a release | [access-and-use.md](access-and-use.md) |
| Rotate credentials, apply guardrails, fix a stuck pipeline | [maintenance.md](maintenance.md) |

## The objects

| Object | One per | Purpose |
|---|---|---|
| Project | module | Groups the module's pipelines; a namespace on the Kargo cluster |
| Warehouse | service | Watches the image and chart; produces Freight |
| Freight | release | Immutable bundle: one image tag plus one chart version |
| Stage | service x environment | Holds the Freight an environment runs; runs the promotion steps |

Kargo objects are never created by hand. They are rendered by the pipeline chart from one config file per project (`deploy-as-code/helm/charts/kargo/config/projects/<project>.yaml`) and applied by Argo CD from git. Editing a pipeline means editing that file and raising a pull request.
