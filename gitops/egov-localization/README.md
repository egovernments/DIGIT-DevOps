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

## Note on the db-migration init container

`initContainers.dbMigration.image.tag` (the `egov-localization-db` init
container) is pinned to the **same freight tag as the main app image**, both
in the Applications' initial parameters and in each Stage's `argocd-update`
step. This matches real production behavior: the existing Jenkins/deployer
pipeline sets `image.tag` and `initContainers.dbMigration.image.tag` together
on every deploy — the chart/common default (`latest`) is never actually used,
and `egovio/egov-localization-db:latest` doesn't even exist on Docker Hub.
Forgetting this the first time caused a stuck rollout (`Init:ImagePullBackOff`)
on `dev` — don't drop this parameter when editing the Stage promotion steps.

## Registry credentials for Kargo image discovery

Kargo's image discovery was failing with Docker Hub's anonymous rate limit
(`TOOMANYREQUESTS`) on every attempt — `egov-localization` has hundreds of
historical tags, and checking "newest build" without auth exhausts the
100-pulls/6hr anonymous limit almost immediately. Fixed by adding a
`kargo.akuity.io/cred-type: image` Secret (`dockerhub-creds`) in this
Project's namespace, reusing the same Docker Hub credentials already present
in the `docker-registry-secret` used for `imagePullSecrets` elsewhere in the
cluster. If image discovery ever silently stops working again, check
`kubectl logs -n kargo deploy/kargo-controller` for `TOOMANYREQUESTS` before
assuming it's a config problem.

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
kargo promote --project egov-localization --warehouse egov-localization --stage dev --wait
kargo promote --project egov-localization --warehouse egov-localization --stage qa  --wait
kargo promote --project egov-localization --warehouse egov-localization --stage uat --wait
```
