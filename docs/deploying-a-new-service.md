# Deploying a New Service

Worked example used below: adding `notify` to `uat-saas` (2026-09-17).

## 1. Pick the category and create the Helm chart

Categories live under `deploy-as-code/helm/charts/<category>/`, e.g. `core-services`, `business-services`, `health-services`, `frontend`, `accelerators`, `backbone-services`. Create `deploy-as-code/helm/charts/<category>/<service>/`:

```
<service>/
  Chart.yaml
  values.yaml
  templates/
    deployment.yaml
    service.yaml
    ingress.yaml   # only if the service is exposed via ingress
```

`Chart.yaml` declares a dependency on the shared `common` chart:

```yaml
apiVersion: v2
name: <service>
description: A Helm chart for Kubernetes
type: application
version: 0.1.0
appVersion: 1.16.0
dependencies:
  - name: common
    version: 0.0.5
    repository: file://../../common
```

Each template file just delegates to the common chart — you don't write raw Kubernetes manifests:

```yaml
# deployment.yaml
{{- template "common.deployment" . -}}
```
```yaml
# service.yaml
{{- template "common.service" . -}}
```
```yaml
# ingress.yaml
{{- template "common.ingress" . -}}
```

`values.yaml` configures the common chart's behavior for this service: labels, `image.repository`, `ingress.context`, `initContainers.dbMigration` (if it needs Flyway migrations), `healthChecks`, `resources`, and an `env:` block (a templated YAML string) for the container's environment variables. See `deploy-as-code/helm/charts/common/README.md` for the full list of knobs the common chart exposes.

The easiest way to write this file correctly is to copy `values.yaml` from a sibling service of the same type (e.g. another Java Spring service in the same category) and adjust names, context path, DB schema table, and env vars.

## 2. Add the environment override block

In `deploy-as-code/helm/environments/<env>.yaml`, add a block for the service (this is merged as a second Helm values file on top of the chart's own `values.yaml`):

```yaml
<service>:
  image:
    tag: <image-tag>
  initContainers:
    dbMigration:
      image:
        tag: <image-tag>
  tracing-export-enabled: "true"
```

Only include keys you need to override — anything not set here falls back to the chart's `values.yaml` default.

If the service needs new secrets (DB creds are already handled generically via the `db` secret — this is only for service-specific secrets, e.g. a new third-party API key), add them to `deploy-as-code/helm/environments/<env>-secrets.yaml`. That file is SOPS-encrypted; edit it with `sops deploy-as-code/helm/environments/<env>-secrets.yaml` rather than a plain editor, and check the existing pattern for how a similar secret is wired into a Deployment's `env` via `secretKeyRef`. If you're not set up with the SOPS decryption key for this environment, hand this step to whoever manages secrets.

## 3. Register it in the ArgoCD ApplicationSet

Find the ApplicationSet file for the environment + category, e.g. `deploy-as-code/helm/charts/argo-cd/egov/<env>-egov-appset-<category>.yaml`, and add an entry to the `generators[0].list.elements` array:

```yaml
- name: <service>
  path: <service>
```

The `path` must match the chart directory name — the template turns it into `deploy-as-code/helm/charts/<category>/{{path}}` as the Helm chart source and (for most categories) `{{name}}` as the ArgoCD Application name.

## 4. Commit and push

```bash
git add deploy-as-code/helm/charts/<category>/<service> \
        deploy-as-code/helm/environments/<env>.yaml \
        deploy-as-code/helm/charts/argo-cd/egov/<env>-egov-appset-<category>.yaml
git commit -m "feat(<env>): add <service>"
git push origin <env-branch>
```

## 5. Apply the ApplicationSet to the cluster (required — see caveat below)

```bash
kubectl config use-context <env-cluster-context>
kubectl apply -f deploy-as-code/helm/charts/argo-cd/egov/<env>-egov-appset-<category>.yaml
```

> The ApplicationSets in this repo use a static inline `list` generator with no automated sync from git to the live `ApplicationSet` resource. Pushing to the branch updates the ArgoCD *source of truth in git*, but the live ApplicationSet in the cluster won't pick up the new entry until you `kubectl apply` the file. Skipping this step means ArgoCD never generates the new Application.

## 6. Verify

```bash
kubectl get application <service> -n argocd
kubectl get pods -n egov | grep <service>
```

Sanity-check before calling it done:

- `SYNC STATUS: Synced`, `HEALTH STATUS: Healthy`
- Pod is `1/1 Running` (if it's stuck at `0/1`, check the readiness probe path in `values.yaml` and, for Java services, whether the DB migration init container completed: `kubectl logs <pod> -c <dbMigration-init-container-name>`)
- If exposed via ingress, hit `https://<env-domain>/<ingress.context>/health` (or the service's health path)
- If the service needs credentials (mail, SMS, third-party APIs), confirm the referenced Kubernetes Secret already exists: `kubectl get secret <secret-name> -n egov`. Don't assume it exists just because `values.yaml` references it — for example `notify` was able to reuse the pre-existing `egov-notification-mail` / `egov-notification-sms` secrets in `uat-saas`, but a brand-new secret requires the SOPS step in Step 2.

## Sample: what "add notify" looked like end-to-end

1. Chart added at `deploy-as-code/helm/charts/core-services/notify/` (Chart.yaml, values.yaml, deployment/ingress/service templates delegating to `common`).
2. `notify:` block added to `deploy-as-code/helm/environments/uat-saas.yaml` with `image.tag`, `initContainers.dbMigration.image.tag`, and `tracing-export-enabled: "true"`.
3. `- name: notify / path: notify` added to `deploy-as-code/helm/charts/argo-cd/egov/uat-saas-egov-appset-core.yaml`.
4. Committed and pushed to `uat-saas`.
5. `kubectl apply -f deploy-as-code/helm/charts/argo-cd/egov/uat-saas-egov-appset-core.yaml` against the `uat-saas` cluster context — this is what actually made the `notify` Application appear.
6. Verified: `kubectl get application notify -n argocd` → `Synced` / `Healthy`; `kubectl get pods -n egov | grep notify` → `1/1 Running`.
