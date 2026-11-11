# Code Build

<sub>Stage 2 of 5 - [Workflows](<../1. Workflows/README.md>) -> **Code Build** -> [Helm Packaging & Releasing](<../3. Helm Packaging & Releasing/README.md>) -> [Kargo Promotions](<../4. Kargo Promotions/README.md>) -> [Argo CD](<../5. Argo CD/README.md>)</sub>

Code Build turns a service's source code into a signed, scanned container image in the registry, using the CI platform described in [Workflows](<../1. Workflows/README.md>). The stages around it:

- **Code Build** (here): a central, reusable GitHub Actions engine builds each
  service image (and its optional `-db` migration image), scans it with Trivy,
  pushes it multi-arch to `docker.io/egovio/<service>`, and signs it with cosign.
- **Helm Packaging & Releasing**: the service chart is packaged and published to
  the Helm repository so a version exists to deploy. See
  [Helm Packaging & Releasing](<../3. Helm Packaging & Releasing/>).
- **Kargo Promotions**: Kargo discovers the new image tag + chart version as
  Freight and promotes it into an environment branch. See
  [Kargo Promotions](<../4. Kargo Promotions/>).
- **Argo CD**: Argo CD reconciles that branch onto the cluster. See
  [Argo CD](<../5. Argo CD/>).

Code Build produces the image tag (`<branch>-<short-sha>`) that everything
downstream keys off. Nothing is promoted or deployed until an image exists here.

## What is in this section

| Doc | Read it to |
|---|---|
| [getting-started.md](getting-started.md) | Understand what the build system is and how a build runs end to end |
| [onboarding-a-service.md](onboarding-a-service.md) | Put a new service repo (or a new service in an existing repo) on Code Build |
| [access-and-use.md](access-and-use.md) | Trigger builds, find the images they produce, and read scan results |
| [maintenance.md](maintenance.md) | Upgrade the build engine, change scan policy, and debug failed builds |

## How it is built (the moving parts)

Code Build is a **reusable workflow** pattern. One engine lives in this repo
(`egovernments/DIGIT-DevOps`); each service repo keeps a thin **caller** that
pins the engine and passes its service list.

| Piece | Where | Role |
|---|---|---|
| Build engine | [`.github/workflows/reusable-build.yaml`](../../.github/workflows/reusable-build.yaml) | `workflow_call` engine: resolve-config -> code-scan -> build -> image-scan -> push -> cosign |
| Setup engine | [`.github/workflows/reusable-setup.yaml`](../../.github/workflows/reusable-setup.yaml) | Scaffolds the caller + Trivy dashboard into a consumer repo and keeps its dropdowns current |
| Tag promoter | [`.github/workflows/promote-reusable-tag.yaml`](../../.github/workflows/promote-reusable-tag.yaml) | Moves `reusable-build-v1` to the latest `master` so callers get engine fixes automatically |
| Caller template | [`templates/consumer/.github/workflows/code-build.yaml`](../../templates/consumer/.github/workflows/code-build.yaml) | The per-repo "Build - Code" workflow, with branch + service pickers |
| Deep-dive docs | [`1. Workflows/`](<../1. Workflows/>) | Full reference: [build.md](<../1. Workflows/build.md>), [setup.md](<../1. Workflows/setup.md>), [onboarding.md](<../1. Workflows/onboarding.md>), [actions-ui.md](<../1. Workflows/actions-ui.md>) |

Callers pin the engine with `@reusable-build-v1`, so an engine fix merged to
`master` reaches every service repo without a per-repo change.
