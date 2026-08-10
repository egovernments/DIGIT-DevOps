# egov-localization: ArgoCD + Kargo promotion

Real, currently-healthy production service (`deploy-as-code/helm/charts/core-services/egov-localization`),
onboarded onto the same ArgoCD + Kargo pattern proven with the `playground` demo
(see `../sample-app/README.md`), with two deliberate differences given this is
live and production-serving:

- **Manual sync only** (`syncPolicy: {}` — no `automated`). ArgoCD will show
  drift but never touch the live Deployment/Service/Ingress in the `egov`
  namespace until someone explicitly runs a sync. Once confidence is built,
  `automated: {prune: true, selfHeal: true}` can be added, matching the
  `sample-app` Applications.
- **Initial `image.tag` matches each cluster's currently-running tag**
  (`redis-localization-key-5c0a4c4`, identical on dev/qa/uat as of setup time)
  so takeover produces zero diff — no forced rollout when the Applications
  are first created.

Reuses the existing `egov` namespace/release and the existing `git-creds`
Secret (used by other charts' `gitSync` init container — not needed by this
chart, but confirms the namespace's secrets are already in place).

## Deliberately out of scope

- `initContainers.dbMigration.image.tag` (the `egov-localization-db` init
  container) is **not** managed here — it stays on the chart/common default
  (`latest`), matching current production behavior. The CI pipeline *does*
  build a matching `egovio/egov-localization-db:<tag>` per commit (there's a
  `db/migration` folder in the source repo), so pinning it to the same freight
  tag as the app is possible later, but that would be a behavior change from
  today's "migration container always floats on latest" — not made here.

## CI

Images are built by `Digit-Core`'s `.github/workflows/build.yaml`
(`workflow_dispatch`, not triggered automatically on push). Tag format is
`<branch>-<shortSHA>`, built for both `amd64`/`arm64` and published as a
proper multi-arch manifest under the clean tag — the Warehouse ignores the
`-amd64`/`-arm64`-suffixed per-arch tags so it never picks a single-arch
image as "newest".

## Usage

```bash
kubectx <unified-dev-context>
kubectl apply -f gitops/egov-localization/

# check for drift before ever syncing anything live
argocd app diff egov-localization-dev --core
argocd app diff egov-localization-qa --core
argocd app diff egov-localization-uat --core

# discover new freight (or wait for the 5m interval)
kubectl patch warehouse egov-localization -n egov-localization --type=merge \
  -p "{\"metadata\":{\"annotations\":{\"kargo.akuity.io/refresh\":\"$(date +%s)\"}}}"
kubectl get freight -n egov-localization

# promote (requires Kargo login, its admission webhook rejects raw kubectl)
kargo login https://localhost:8081/kargo --admin --password admin123 --insecure-skip-tls-verify
kargo promote --project egov-localization --stage dev --freight-latest-available -f
kargo promote --project egov-localization --stage qa  --freight-latest-available -f
kargo promote --project egov-localization --stage uat --freight-latest-available -f
```
