# studio-demo: Jenkins -> Argo CD migration

GitOps definition for the **studio-demo** cluster (Azure AKS). This replaces the
Jenkins `builds.digit.org` + Go deployer (`deploy-as-code/deployer`, which did
`helm template | kubectl apply` with image tags injected at deploy time) with
Argo CD syncing from this repo.

- **Source repo / branch:** `https://github.com/egovernments/DIGIT-DevOps.git` @ `studio-demo` (public, cloned anonymously)
- **Charts:** `deploy-as-code/helm/charts/<module>/<service>`
- **Env overlay:** `deploy-as-code/helm/environments/studio-demo.yaml`
- **Pattern:** mirrors `health-campaign-devops` @ `azure-install-hcm-demo-v2`
- **Scope:** Argo CD only. No Kargo / promotion workflow.

Everything here was authored and validated locally. **Nothing has been applied to
the cluster yet** - this is the Friday-first-half cutover package.

---

## How adoption works (read this first)

studio-demo's workloads are already running, applied raw by the Go deployer (no
Helm releases exist - `helm list -A` is empty). The Applications here are tuned to
**adopt those objects in place** rather than recreate them:

- `syncPolicy.automated.prune: false` - never delete on first sync.
- `selfHeal: true` - reconcile drift back to git.
- `ServerSideApply=true` + `ApplyOutOfSyncOnly=true` - take ownership of the
  existing objects via SSA field management instead of replacing them.

Because the DIGIT charts name every object from `.Values.name` (not from the Helm
release name), and backbone charts that do use `.Release.Name` are pinned with
`releaseName: release-name`, Argo CD renders the **exact same object names,
namespaces and images** that are live today. This was verified for all 39 app
services by rendering each chart with its value files and diffing name / namespace
/ image against the cluster (all 39 matched - see "Validation" below).

**Expect a one-time rolling restart on ~13 services, not zero.** A full spec diff
(image / replicas / resources / env / ports / args) against the live cluster found
that object identity and images match everywhere, but the git charts carry newer
**env** than the running pods (they were last deployed by the Go deployer from older
chart renders) - mostly additive vars like `JAVA_ARGS`,
`SPRING_DATASOURCE_DRIVER_CLASS_NAME`, gateway hook/whitelist URLs, egov-user MDMS
endpoints. On first sync `selfHeal` applies these, so those pods roll once to pick up
the newer config. This is expected and safe. Two items that were live-vs-git
mismatches have already been reconciled in git before cutover: egov-localization
`replicas` pinned 3->1 to match the running count (no HPA), and pdf-service
`data-config-urls` / `format-config-urls` in `studio-demo.yaml` rebuilt as the union
of the live + git lists (git had been missing 38 PDFs the live pod serves). The only
remaining non-additive diff is egov-workflow-v2 losing a `LOGGING_LEVEL_*` env var,
which is cosmetic.

### Image tags are now in git

The Jenkins/Go deployer injected `--set image.tag=<build>` at deploy time, so git
never carried the running versions. Under Argo CD the tag must live in git, so each
egov / health / studio service carries its running `image.tag` (and, for the ~26
services that have a db-migration init container, `initContainers.dbMigration.image.tag`)
inline in its `studio-demo.yaml` block, frozen from the live cluster at cutover.

**To promote a new build from now on:** bump the service's `image.tag` in
`studio-demo.yaml` and let Argo CD sync (this is the GitOps replacement for a
Jenkins deploy job).

---

## One-time bootstrap (Friday, before applying the apps)

### 1. Install Argo CD (vendored chart)

```bash
export KUBECONFIG=~/.kube/studio-demo
kubectl create namespace argocd
cd deploy-as-code/helm/charts/backbone-services/argo-cd
helm dependency build
helm -n argocd install argocd . -f values.yaml
```

The chart is based on unified-dev's argo-cd chart (the eGov Azure reference), with a
single curated `values.yaml` adapted to studio-demo (domain, `/argocd` subpath, and
the Azure Key Vault sops wiring below). It brings up Argo CD v3.3.3 served at
**https://studio-demo.digit.org/argocd** (path-based via `--rootpath`/`--basehref`,
TLS via cert-manager `letsencrypt-prod`, nginx terminates TLS). The repo-server
ships the helm-secrets / sops config-management plugin and decrypts via Azure
workload identity (no AKS workload-identity addon needed - the federated token is
projected explicitly; only the AKS OIDC issuer is required, already enabled).

Initial admin password:
```bash
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

### 2. Repository credential - none needed

`egovernments/DIGIT-DevOps` is a **public** repo and every Application/AppProject
here points at `https://github.com/egovernments/DIGIT-DevOps.git`, so Argo CD clones
it anonymously over HTTPS. No repository secret is created (matches unified-dev and
hcm-demo-v2, whose argo-cd chart also ships `credentialTemplates: {}` /
`repositories: {}` empty). Nothing to do at bootstrap.

### 3. sops decryption via Azure Key Vault (already provisioned)

studio-demo's secrets are sops-encrypted with **Azure Key Vault** (not AWS KMS),
matching unified-dev's digit3 pattern. The repo-server decrypts them via Azure
workload identity - **no secret to create at bootstrap**, it is wired in `values.yaml`
(`repoServer.env` AZURE_* + projected `azure-token`). These Azure resources were
already created during this migration (subscription githubopensourcefund, RG
studio-demo):

| Resource | Value |
|---|---|
| Key Vault | `studio-demo-sops-kv` (RBAC), key `sops` |
| Key URL | `https://studio-demo-sops-kv.vault.azure.net/keys/sops/36be6f8a9a4e46ec912a5f7ece678b3a` |
| Managed identity | `argocd-sops-studio-demo` (clientId `17e53842-d296-410d-a86d-31a7b2c91552`) |
| Vault role | `Key Vault Crypto User` -> the identity |
| Federated credential | issuer = studio-demo AKS OIDC, subject = `system:serviceaccount:argocd:argocd-repo-server`, aud = `api://AzureADTokenExchange` |

This is **only** needed for the `cluster-configs` Application (the app services do
not use `secrets://`). The `.sops.yaml` rule routes `studio-demo-secrets.yaml` to
this vault. To edit secrets locally you need `Key Vault Crypto User` on the vault
(`az login`), then `sops environments/studio-demo-secrets.yaml`.

---

## Apply order (the cutover)

One manual step: apply the root app-of-apps. It syncs the whole `charts/argo-cd`
tree (except `bootstrap/`), so Argo CD creates every AppProject + ApplicationSet +
standalone Application itself, and the appsets then generate the per-service apps.
From then on a push to `studio-demo` is enough.

```bash
export KUBECONFIG=~/.kube/studio-demo
kubectl apply -f deploy-as-code/helm/charts/argo-cd/bootstrap/studio-demo-bootstrap.yaml
```

Watch the projects/appsets appear, then the per-service Applications reach
**Synced/Healthy**. Because every app ships `prune:false`, a mistake cannot delete
a workload; worst case an app shows OutOfSync and you investigate before syncing.

<details><summary>Manual apply (if you skip the bootstrap)</summary>

```bash
cd deploy-as-code/helm/charts/argo-cd
kubectl apply -f cluster-configs/cluster-configs-app-project.yaml
kubectl apply -f backbone-services/backbone-services-app-project.yaml
kubectl apply -f monitoring/monitoring-app-project.yaml
kubectl apply -f egov/egov-app-project.yaml
kubectl apply -f health/health-app-project.yaml
kubectl apply -f studio/studio-app-project.yaml
kubectl apply -f cluster-configs/cluster-configs-application.yaml
kubectl apply -f backbone-services/backbone-services-app-set.yaml
kubectl apply -f monitoring/monitoring-app-set.yaml
kubectl apply -f egov/egov-app-set-core.yaml
kubectl apply -f egov/egov-app-set-common.yaml
kubectl apply -f health/health-app-set.yaml
kubectl apply -f studio/studio-app-set.yaml
kubectl apply -f studio/digit-a11y-application.yaml
```
</details>

Grafana needs a GitHub OAuth app (callback `https://studio-demo.digit.org/monitoring/login/github`); put its
`clientID`/`clientSecret` in `cluster-configs.secrets.grafana` (sops) before syncing `monitoring-grafana`,
else the grafana pod stays in `CreateContainerConfigError` (missing `grafana-oauth` Secret). The alertmanager
slack webhook and grafana admin password are already in sops.

Recommended: apply the ApplicationSets but watch the first few Applications reach
**Synced/Healthy** before moving on. Because `prune:false`, a mistake cannot delete
a workload; worst case an app shows OutOfSync and you investigate before syncing.

---

## What is managed

| Project | Namespace(s) | Services |
|---|---|---|
| `cluster-configs-project` | all | namespaces, configmaps, secrets, RBAC, root ingress |
| `backbone-services-project` | backbone, egov, playground | ingress-nginx, cert-manager, elasticsearch-master/data, kafka-kraft, redis, kibana, pgadmin, playground, oauth2-proxy |
| `monitoring-project` | monitoring, backbone, kube-system | kube-prometheus-stack (prometheus + alertmanager), grafana, blackbox-exporter, matomo, kafka-ui |
| `egov-project` | egov | 20 core (incl egov-user) + 4 common services |
| `health-project` | health | beneficiary-idgen, health-individual, health-service-request |
| `studio-project` | studio | 10 studio services + digit-a11y |

`digit-a11y` is the only standalone `Application` (its chart sits one directory
deeper, `studio-services/agent/digit-a11y`). `egov-user` is in the core
ApplicationSet; its chart values were renamed `egov-user-values.yaml` ->
`values.yaml` so it needs no extra value file.

---

## Validation (per app and fleet-wide)

```bash
argocd app list                       # all Synced/Healthy, none Progressing
argocd app diff egov-idgen       # expect no diff (adoption, not change)
argocd app get cluster-configs

# no pods should have restarted from the cutover:
kubectl get pods -A --sort-by=.status.startTime | tail -40
```

Local pre-flight already done on this branch (render == live cluster for all 39
services). Re-run it any time with the dry-run in the migration notes.

### cluster-configs prune

`cluster-configs` ships with `prune:false` for the first adoption, because a prune
could delete a live configmap/secret not yet represented in git. After confirming
`argocd app diff cluster-configs` is clean, you may flip it to
`prune:true` to match hcm-demo-v2.

---

## Rollback

Argo CD is additive and non-destructive here (`prune:false`), so rolling back does
not touch the running workloads:

```bash
# Stop Argo CD from managing a layer WITHOUT deleting its workloads:
kubectl delete applicationset studio-demo-egov-appset-core -n argocd
kubectl delete application  egov-idgen -n argocd --cascade=orphan
```

`--cascade=orphan` (or deleting the ApplicationSet, whose child Applications have no
delete finalizer) leaves every Deployment/Service/etc. running. The Go deployer
(`deploy-as-code/deployer`) can then resume as before. Only remove the Argo CD
install itself (`helm -n argocd uninstall argocd`) after the whole migration is
abandoned - it does not own any studio-demo workload.
```
