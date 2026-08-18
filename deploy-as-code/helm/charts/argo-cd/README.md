# ArgoCD-managed cluster configs (digit-lts AKS)

Ports the ArgoCD + SOPS + AWS KMS integration from `HCM-KEBBI/kebbi-devops`
(`docs/argocd-sops-aws-kms-integration.md`, commit `11daa08`) to the Azure AKS
cluster `digit-lts` in this repo.

## Layout

| File | Purpose |
|---|---|
| `cluster-configs/cluster-configs-application.yaml` | ArgoCD `Application` rendering `charts/cluster-configs` with the `digit-lts` env values |
| `cluster-configs/cluster-configs-app-project.yaml` | The `AppProject` it belongs to |
| `../backbone-services/argo-cd/values-azure-aks.yaml` | Values overlay that teaches `argocd-repo-server` to decrypt `secrets://` values files |

The encryption key mapping is unchanged and already present in
`deploy-as-code/helm/.sops.yaml`: `environments/digit-lts-secrets.yaml` is bound
to `arn:aws:kms:ap-south-1:218381940040:key/9a3b0835-7713-4925-8b3d-da7e421d28d2`,
which matches the KMS ARN already embedded in that file's `sops:` metadata.

## The one deviation from the source doc

The doc authenticates to AWS KMS with **EKS IRSA** — an
`eks.amazonaws.com/role-arn` annotation on the `argocd-repo-server` service
account, which the EKS Pod Identity webhook turns into injected AWS credentials.

**AKS has no such webhook, so that annotation does nothing here.** The overlay
instead sets `AWS_ROLE_ARN` and `AWS_WEB_IDENTITY_TOKEN_FILE` explicitly and
mounts a projected service account token with audience `sts.amazonaws.com`. The
underlying flow is the same one IRSA uses — `sts:AssumeRoleWithWebIdentity`
against a projected token — and it preserves the doc's core property: no
long-lived AWS access keys stored in the cluster.

## Prerequisites (not created by these manifests)

1. AKS cluster has an OIDC issuer enabled:
   ```bash
   az aks show -g <rg> -n <aks-cluster> --query oidcIssuerProfile.issuerURL -o tsv
   ```
2. That issuer URL is registered in AWS account `218381940040` as an IAM OIDC
   identity provider.
3. IAM role `argocd-rs-digit-lts-sops-web-identity` exists, with a trust policy
   federated to that provider and conditioned on:
   - `aud` = `sts.amazonaws.com`
   - `sub` = `system:serviceaccount:argocd:argocd-repo-server`
4. That role has `kms:Decrypt` on the KMS key above, and the key policy permits
   the role.

## Install

```bash
helm repo add argo https://argoproj.github.io/argo-helm
helm upgrade -i argocd argo/argo-cd -n argocd --create-namespace \
  -f deploy-as-code/helm/charts/backbone-services/argo-cd/values-azure-aks.yaml

kubectl apply -f deploy-as-code/helm/charts/argo-cd/cluster-configs/cluster-configs-app-project.yaml
kubectl apply -f deploy-as-code/helm/charts/argo-cd/cluster-configs/cluster-configs-application.yaml
```

## Verify

```bash
# Projected AWS token present, and no static keys
kubectl -n argocd exec deploy/argocd-repo-server -- env | grep AWS_
kubectl -n argocd exec deploy/argocd-repo-server -- cat /var/run/secrets/aws/token | head -c 20

# Tooling landed in the shared emptyDir
kubectl -n argocd exec deploy/argocd-repo-server -- /gitops-tools/sops --version

# Then sync and watch for sops AccessDenied / credential errors
kubectl -n argocd logs deploy/argocd-repo-server | grep -i -E 'sops|accessdenied'
```
