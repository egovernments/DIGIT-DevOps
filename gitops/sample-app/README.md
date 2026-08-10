# Sample app: ArgoCD + Kargo promotion demo

Demonstrates deploying the existing `playground` chart
(`deploy-as-code/helm/charts/backbone-services/playground`) to `unified-dev`
via ArgoCD, then promoting it through `unified-qa` and `unified-uat` with
Kargo. This is additive infrastructure for a demo — it does not replace the
Jenkins/deployer pipeline that manages the `playground` release today. Since
both target the same `playground` namespace/release, avoid running the
Jenkins deploy job for `playground` while ArgoCD manages it, to prevent the
two from fighting over the same Deployment.

ArgoCD only runs on `unified-dev` (hub-and-spoke); `unified-qa` and
`unified-uat` are registered as remote clusters named `unified-qa` and
`unified-uat` in that instance.

## Layout

- `application-dev.yaml` / `application-qa.yaml` / `application-uat.yaml` —
  one ArgoCD `Application` per stage. Each is a multi-source app: the
  `playground` chart plus `common/values.yaml` as an extra value file (the
  chart's own template relies on keys only defined in `common`'s defaults —
  see the `common` chart dependency in `playground/Chart.yaml`). The
  `image.tag` Helm parameter is what Kargo patches on promotion.
- `kargo-project.yaml` — Kargo `Project` `sample-app` (creates the
  `sample-app` namespace).
- `kargo-warehouse.yaml` — subscribes to `egovio/playground` tags on Docker
  Hub (`NewestBuild` strategy, since existing tags aren't consistent SemVer).
- `kargo-stages.yaml` — `dev` → `qa` → `uat` Stages. Each stage's
  `promotionTemplate` runs a single `argocd-update` step that patches that
  stage's Application's `image.tag` Helm parameter directly (no git
  write-back).

Each Application carries `kargo.akuity.io/authorized-stage:
"sample-app:<stage>"`, which is what authorizes the matching Kargo Stage to
update it.

## Usage

```bash
kubectx <unified-dev-context>
kubectl apply -f gitops/sample-app/

# watch discovered freight
kubectl get freight -n sample-app

# promote freight into a stage (repeat dev -> qa -> uat)
kargo promote --project sample-app --stage dev --freight-latest-available -f
kargo promote --project sample-app --stage qa --freight-latest-available -f
kargo promote --project sample-app --stage uat --freight-latest-available -f

# or via UI at https://unified-dev.digit.org/kargo
```
