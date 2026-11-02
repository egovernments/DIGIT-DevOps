# 02 Prerequisites and Installation

What must exist before applications can be onboarded, and how each piece is installed. Steps marked **(Kargo)** are needed only for the Kargo + Argo CD model.

## Prerequisites

| Item | Requirement |
|---|---|
| Kubernetes clusters | One per environment (for example dev, qa, uat). Kargo runs on one of them (usually dev). |
| Git repository | `<org>/<repo>`, with one protected branch per environment and pull-request reviews required |
| Helm repository | Packaged charts published to `https://helm.digit.org` (or its sub-path for your charts) |
| Container registry | Images `docker.io/<registry-org>/<service>` (and `<service>-db` for migrations) |
| Tag convention | Build tags that identify the source branch and commit, for example `master-<sha>` and `<branch>-<sha>`; per-architecture variants suffixed `-amd64` / `-arm64` |
| Encryption key | A key for SOPS: Azure Key Vault key or AWS KMS key, one per environment group |
| Identity | Workload identity (Azure) or IRSA (AWS) for Argo CD's repo-server to use the encryption key; an SSO provider for Kargo (GitHub OAuth via Dex is the reference setup) |
| Local tools | `kubectl`, `helm` 3, `sops`, `git`, and the Kargo / Argo CD CLIs (optional) |

Reference versions: Argo CD 3.3, Kargo 1.11, Argo Rollouts 1.x (only for post-promotion verification).

## Step 1: Install Argo CD on each cluster

1. **Install Argo CD** in namespace `argocd` with its Helm chart.
2. **Enable SOPS decryption in the repo-server** so value files referenced as `secrets://…` (and SOPS files read through a `$values` source) are decrypted at render time:
   - install the helm-secrets plugin and SOPS in the repo-server;
   - give the repo-server's identity **decrypt** permission on the environment's key, for example *Key Vault Crypto User* on the Azure key, or `kms:Decrypt` on the AWS key.
3. **Register repositories** if they are private. A public Helm repository and a public git repository need no credentials.
4. **Apply the bootstrap Application once**, from [templates/argocd/bootstrap-application.yaml](templates/argocd/bootstrap-application.yaml):

   ```sh
   kubectl apply -f bootstrap-application.yaml
   ```

   From then on, every manifest under `<argocd-dir>/<env>/` on the environment branch is applied automatically.

## Step 2: Prepare the environment branch

On each `<env-branch>`, create:

| Path | From template |
|---|---|
| `<argocd-dir>/<env>/<module>/<module>-app-project.yaml` | [templates/argocd/appproject.yaml](templates/argocd/appproject.yaml) |
| `<argocd-dir>/<env>/<module>/<module>-app-set.yaml` (Argo CD only) | [templates/argocd/applicationset-argocd-only.yaml](templates/argocd/applicationset-argocd-only.yaml) |
| `<argocd-dir>/<env>/kargo-managed/*.yaml` (Kargo) | [templates/argocd/applicationset-kargo-managed-*.yaml](templates/argocd) |
| `<argocd-dir>/<env>/<module>/<module>-config-application.yaml` | [templates/argocd/config-application.yaml](templates/argocd/config-application.yaml) |
| `<environments-dir>/<module>-<env>.yaml` | [templates/environments/module-env.yaml](templates/environments/module-env.yaml) |
| `<environments-dir>/<module>-<env>-secrets.yaml` | [templates/environments/module-env-secrets.example.yaml](templates/environments/module-env-secrets.example.yaml), then encrypted |
| Rule in `.sops.yaml` | [templates/environments/sops.yaml](templates/environments/sops.yaml) |

See [03 Repository Layout and Conventions](03-repository-layout-and-conventions.md) for naming.

## Step 3 (Kargo): Install the Kargo control plane

On the cluster chosen for Kargo:

1. **Install Argo Rollouts**, only if you will use post-promotion verification.
2. **Install Kargo** with its upstream chart (`oci://ghcr.io/akuity/kargo-charts/kargo`), as an Argo CD Application in its own AppProject. Configure:
   - SSO (for example Dex with a GitHub connector, `teamNameField: slug`, so team claims look like `<github-org>:<team-slug>`);
   - the admin account (password hash and token-signing key stored as a Secret);
   - the namespaces scanned for cluster-level team ServiceAccounts (`GLOBAL_SERVICE_ACCOUNT_NAMESPACES`, default the Kargo namespace).
3. **Credentials per project namespace**, as Secrets labelled for Kargo:

   | Secret label `kargo.akuity.io/cred-type` | Used for |
   |---|---|
   | `image` | Reading tags from the container registry (avoid anonymous rate limits) |
   | `git` | Cloning and pushing the environment branches |
   | `helm` | Only for private Helm repositories |

   Keep these values SOPS-encrypted in git and render them with your config chart.
4. **Pipelines ApplicationSet**: add [templates/argocd/kargo-pipelines-applicationset.yaml](templates/argocd/kargo-pipelines-applicationset.yaml). It renders each project's Kargo objects from its project config. Teams not using the pipeline chart can apply the raw manifests in [templates/kargo/manifests](templates/kargo/manifests) through an Argo CD Application instead.

## Step 4: Verify the installation

| Check | Expected |
|---|---|
| `kubectl -n argocd get app <env>-bootstrap` | Synced, Healthy |
| `kubectl -n argocd get appproject,applicationset` | Your module's AppProject and ApplicationSets exist |
| (Kargo) `kubectl -n argocd get app kargo-<project>` | Synced |
| (Kargo) Kargo UI | The project is listed; each Warehouse is Ready, or Not Ready only because no matching build exists yet |
| A test decrypt: render the config Application | No SOPS errors in the Application's conditions |

## Next steps

- Onboard applications: [04 Kargo Guide](04-kargo-guide.md), [05 Argo CD Guide](05-argocd-guide.md).
- Configure module settings and secrets: [06 Configuration and Secrets](06-configuration-and-secrets.md).
- Grant access: [07 Access Control](07-access-control.md).
