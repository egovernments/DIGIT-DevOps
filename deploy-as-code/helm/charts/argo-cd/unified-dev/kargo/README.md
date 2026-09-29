# Kargo on unified-dev

Kargo control plane + promotion pipelines via ArgoCD. UI at **https://kargo.digit.org**.

**Model:** a Kargo **project** is a module (`unified-core` = core services →
`environments/unified-<stage>.yaml`; `unified-health` = health services →
`environments/unified-health-<stage>.yaml`); a **stage** is an environment
(DEV → QA → UAT). One control-plane instance serves all of them.

## Applications

| File | Purpose |
|---|---|
| `kargo-app-project.yaml` | `kargo-project` AppProject |
| `kargo-application.yaml` | Control plane — multi-source (upstream chart `ghcr.io/akuity/kargo-charts/kargo:1.11.4` + `config/control-plane.yaml` via `$values`), same pattern as `monitoring-applications.yaml` |
| `kargo-app-set-pipelines.yaml` | ApplicationSet (`unified-dev-kargo-appset-pipelines`): one `kargo-<project>` Application per list element, same shape as `egov-app-set-core.yaml` |

## Onboard / change a project

Add a list element in `kargo-app-set-pipelines.yaml` and a matching
`charts/kargo/config/projects/<project>.yaml` (a `kargo:` overlay: project + services +
stages) — exactly like adding a service to `egov-app-set-core.yaml`. Chart:
`deploy-as-code/helm/charts/kargo`.

Stages carry a `kargo.akuity.io/color` per env (DEV `#3BA9C2`, QA `#D64550`, UAT `#F2C230`).
Promotion chain DEV → QA → UAT writes tags into `unified-dev.yaml` / `unified-qa.yaml` /
`unified-uat.yaml` on `unified-env-lts`; only DEV runs `argocd-update` (same cluster).

## Credentials

Rendered by the **cluster-configs** chart from `cluster-configs.secrets.kargo`:
- non-secret metadata (`projects`, `adminSecret.enabled/name/namespace`) in `charts/cluster-configs/values.yaml`
- credentials (`adminSecret.passwordHash/tokenSigningKey`, `imageCredentials`, `gitCredentials`) SOPS-encrypted in `unified-dev-secrets.yaml`
- template `charts/cluster-configs/templates/secrets/kargo-secret.yaml` renders `image-creds-*` / `git-creds-*` per project namespace and `kargo-api` in `kargo`

Edit secrets with `AWS_PROFILE=egov sops environments/unified-dev-secrets.yaml`.

## DNS

Point `kargo.digit.org` at the nginx LB IP; cert-manager (`letsencrypt-prod`) issues the cert.

Background: `kargo-setup-runbook.md`.
