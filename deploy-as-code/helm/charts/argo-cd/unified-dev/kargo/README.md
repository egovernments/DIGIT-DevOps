# Kargo on unified-dev

Kargo control plane + promotion pipelines, installed via ArgoCD on the unified-dev
AKS cluster. UI at **https://kargo.digit.org**.

## Applications

| File | Purpose |
|---|---|
| `kargo-app-project.yaml` | `kargo-project` AppProject (CRDs/webhooks/cluster-RBAC whitelisted) |
| `kargo-application.yaml` | Control plane — upstream chart `ghcr.io/akuity/kargo-charts/kargo:1.11.4`, values from `environments/kargo-unified-dev.yaml` |
| `kargo-unified-core-application.yaml` | `unified-core` project: Project/ProjectConfig + Warehouses/Stages for the notification services |
| `kargo-unified-health-application.yaml` | `unified-health` project: scaffold only (no services yet) |

Pipeline config (project, services, stages) lives under the `kargo:` key in the
existing env files (`environments/unified-dev.yaml`,
`environments/unified-health-dev.yaml`) and is rendered by the
`deploy-as-code/helm/charts/kargo/kargo-pipelines` chart. Promotion chain is
DEV → QA → UAT, each stage writing image tags into `unified-dev.yaml` /
`unified-qa.yaml` / `unified-uat.yaml` on `unified-env-lts`. Only DEV runs
`argocd-update` (same cluster as Kargo); QA/UAT are cross-cluster git-push.

## Credentials

Kargo's credential Secrets are rendered by the **cluster-configs** chart (single
owner), not by kargo-pipelines:

- Non-secret metadata (`projects` list) in
  `charts/cluster-configs/values.yaml` → `cluster-configs.secrets.kargo`.
- Sensitive values in `environments/unified-dev-secrets.yaml` →
  `cluster-configs.secrets.kargo` (`adminSecret`, `imageCredentials`,
  `gitCredentials`), decrypted by argocd-repo-server via SOPS + AWS KMS.
- Template: `charts/cluster-configs/templates/secrets/kargo-secret.yaml`
  renders `image-creds-*` / `git-creds-*` into each project namespace and
  `kargo-api` (admin) into the `kargo` namespace.

Edit the secrets with `AWS_PROFILE=egov sops environments/unified-dev-secrets.yaml`.

## DNS

Point `kargo.digit.org` at the nginx ingress LB IP (same as `unified-dev.digit.org`).
cert-manager (`letsencrypt-prod`) issues the cert once DNS resolves.

Full background: `kargo-setup-runbook.md`.
