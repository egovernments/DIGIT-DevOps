# Argo CD configuration — Azure AKS `unified-dev`

Deploys the DIGIT platform onto the Azure AKS cluster `unified-dev`
(`unified-dev-rg`, centralindia, OIDC issuer enabled), mirroring what runs today
in the EKS `unified-dev` cluster. Layout and style follow the `digit-lts` branch.

Scope: namespaces `egov`, `backbone`, `care`, `health`, `studio`, `urban`.

## Layout

```
charts/argo-cd/
├── cluster-configs/
│   ├── cluster-configs-app-project.yaml     # cluster-configs-project
│   └── cluster-configs-application.yaml     # 5 Applications — the only secrets:// users
├── backbone/  backbone-app-project.yaml  + backbone-app-set-backbone.yaml
├── care/      care-app-project.yaml      + care-app-set-care.yaml
├── egov/      egov-app-project.yaml      + 12 egov-app-set-*.yaml
├── health/    health-app-project.yaml    + 3 health-app-set-*.yaml
├── studio/    studio-app-project.yaml    + studio-app-set-studio.yaml
└── urban/     urban-app-project.yaml     + 3 urban-app-set-*.yaml
```

7 `AppProject`s, 21 `ApplicationSet`s covering **175 charts**, 5 `Application`s.
One app-set per (namespace, chart group), named
`unified-dev-<ns>-appset-<group>`, generating Applications named `<ns>-<chart>`.

## The Argo CD chart itself — one values.yaml, no overlays

The full upstream chart is vendored at
`charts/backbone-services/argo-cd/` (argo-cd `9.4.10`, appVersion `v3.3.3`,
168 files including `templates/` and the `redis-ha` subchart).

**Deployment uses a single `values.yaml` and no `-f` flags.** This branch
(`unified-env-lts`) *is* the unified-dev environment, so the chart's own
`values.yaml` holds this environment's configuration directly — the same pattern
the `digit-lts` branch uses, where its `values.yaml` carries `test-lts.digit.org`
and the digit-lts role. Helm loads `values.yaml` automatically, so:

```bash
helm upgrade -i argocd deploy-as-code/helm/charts/backbone-services/argo-cd -n argocd
```

is the whole command. Environment differences are carried by the branch, not by
per-env overlay files. What this branch's `values.yaml` sets for unified-dev:

| Key | Value |
|---|---|
| `global.domain` | `unified-dev.digit.org` |
| `configs.cm.helm.valuesFileSchemes` | `secrets, secrets+literal, https` |
| `repoServer.env` | helm-secrets/sops vars + `AWS_ROLE_ARN` = `argocd-rs-unified-dev-sops-web-identity` |
| `repoServer.initContainers` | `download-tools` (sops 3.9.3, helm-secrets 4.7.7) |
| `repoServer.serviceAccount.name` | `argocd-repo-server` (pinned — it is the IAM trust policy's `sub`) |
| `repoServer.resources` | `500m`/`1Gi` limits, `100m`/`256Mi` requests |
| `crds.install` | `false` (installed server-side, see below) |
| `server.insecure` | `true` (TLS terminates at nginx) |

Verified by rendering with no extra flags: ingress host `unified-dev.digit.org`
at `/argocd`, `cm url` `https://unified-dev.digit.org`, the
`applicationset-controller` present (required by the app-sets), both init
containers, and the correct role ARN.

Two files were **removed** as part of this: `values-unified-dev.yaml` (folded in —
it also set a non-existent `applicationSet.enabled` key, a no-op in 9.4.10) and
`values-with-sops.yaml` (a copy belonging to the `mc-nigeria-uat` environment).

RBAC is inherited from the digit-lts values and still grants the
`argocd-central-uat-*` groups — **rename those to the unified-dev groups** before
handing the UI to users.

## Values wiring

Each namespace uses its own product env file — the EKS cluster runs several
products side by side with different values *and different image tags*, so a
single `unified-dev.yaml` does not work (e.g. `pgr-services` only renders against
the urban file):

| Namespace | Env file |
|---|---|
| `egov`, `backbone` | `environments/unified-dev.yaml` |
| `health` | `environments/unified-health-dev.yaml` |
| `urban` | `environments/unified-urban-dev.yaml` |
| `studio` | `environments/unified-studio-dev.yaml` |
| `care` | `environments/unified-care-dev.yaml` |

**Image tags live in those env files**, in the repo's existing style:

```yaml
pgr-services:
  image:
    tag: "re-enable-boundary-mdms-validation-8426e2e"
  initContainers:
    dbMigration:
      image:
        tag: "re-enable-boundary-mdms-validation-8426e2e"
```

The charts declare `image.repository` but no tag, and `charts/common` hard-fails
with `Tag is mandatory` — the deployer used to inject it at deploy time. The tags
currently committed are the ones live on EKS when these files were generated:
97 in `unified-dev.yaml`, 46 in `unified-health-dev.yaml`, 36 in
`unified-urban-dev.yaml`, 8 in `unified-studio-dev.yaml`, 2 in
`unified-care-dev.yaml` (plus db-migration init tags). **To roll out a new build,
bump the tag in the env file** — no change needed here.

`*-app-set-*-altvalues.yaml` exists for charts that ship `<chart>-values.yaml`
instead of `values.yaml` (currently only `core-services/egov-user`); Helm does not
auto-load those, so the file is named explicitly via `'{{name}}-values.yaml'`.

`targetRevision` is **`unified-env-lts`** on every manifest — the branch these
files and charts live on. Push the branch before syncing.

## SOPS

Only the 5 `cluster-configs` Applications use `secrets://`; each product secrets
file contains a `cluster-configs:` key and nothing else, so the 175 service
Applications skip decryption entirely. All five are bound to
`arn:aws:kms:ap-south-1:218381940040:key/9a3b0835-...` by
`deploy-as-code/helm/.sops.yaml` (rules already present), and all five were
verified to decrypt (46 secret entries total).

`unified-dev`'s cluster-configs creates every namespace; the urban and health
Applications set `cluster-configs.namespaces.create=false` so a single Application
owns each `Namespace` object (studio and care already ship `create: false`).

## Bootstrap

1. **AWS (one-time).** This cluster has its own OIDC issuer
   (`.../66618056-d706-4e51-9a6f-dacdcd563292/`) — the digit-lts role will not
   work. Register it as an IAM OIDC provider (client-id `sts.amazonaws.com`,
   thumbprint `df3c24f9bfd666761b268073fe06d1cc8d4f82a4`), then create
   `argocd-rs-unified-dev-sops-web-identity` trusting it with
   `<url>:aud = sts.amazonaws.com` and
   `<url>:sub = system:serviceaccount:argocd:argocd-repo-server`, plus
   `kms:Decrypt` on the key above. Build the condition-key prefix from what
   `aws iam get-open-id-connect-provider` returns — IAM keeps the trailing slash,
   and a mismatch shows up only as an opaque `AccessDenied`.

2. **CRDs, server-side.** `values.yaml` sets `crds.install: false`: the three CRDs
   total ~1.8 MB, so client-side `kubectl apply` fails on the 256 KB
   `last-applied-configuration` annotation cap. Install them out-of-band first:

   ```bash
   helm template argocd deploy-as-code/helm/charts/backbone-services/argo-cd \
     -n argocd --set crds.install=true -s 'templates/crds/*.yaml' \
     | kubectl apply --server-side -f -
   ```

   That yields `applications.argoproj.io`, `applicationsets.argoproj.io` and
   `appprojects.argoproj.io`. Re-run it on Argo CD version bumps.

3. **Argo CD** — no `-f` needed, `values.yaml` is the environment's config:

   ```bash
   helm upgrade -i argocd deploy-as-code/helm/charts/backbone-services/argo-cd \
     -n argocd --create-namespace
   ```

4. **Projects, then cluster-configs, then the app-sets:**

   ```bash
   kubectl apply -f deploy-as-code/helm/charts/argo-cd/cluster-configs/
   kubectl apply -R -f deploy-as-code/helm/charts/argo-cd/egov/ \
                    -f deploy-as-code/helm/charts/argo-cd/backbone/ \
                    -f deploy-as-code/helm/charts/argo-cd/health/ \
                    -f deploy-as-code/helm/charts/argo-cd/urban/ \
                    -f deploy-as-code/helm/charts/argo-cd/studio/ \
                    -f deploy-as-code/helm/charts/argo-cd/care/
   ```

   Wait for `cluster-configs-unified-dev` to sync first — it creates the
   namespaces the app-sets target (they run with `CreateNamespace=false`).

## Known gaps

- **DNS.** `unified-dev.digit.org` still resolves to the EKS ELB
  (`a2e90498...ap-south-1.elb.amazonaws.com`). Repoint it at the AKS ingress
  LoadBalancer, and make sure the ingress host matches the name that points at
  AKS — a mismatch here is what silently broke the digit-lts UI.
- **Backing services still point at AWS.** `unified-dev.yaml` keeps
  `db-host: unified-dev-db-new...rds.amazonaws.com` and an `es-host` in
  `es-upgrade`. These need Azure equivalents; left untouched rather than guessed.
- **No chart in this repo** for 15 `egov` workloads (`campaign-mfe`,
  `core-digit-ui`, `dss-ui`, `karnataka-ui`, `microplan-mfe`, `ui`,
  `vehicle-tracker`, `workbench-mfe`, `works-ui`, four `my-clickstack-*`, and
  cert-manager's `cainjector`/`webhook`) and 8 `care` workloads (`celery-worker`,
  four `radiology-*`, three `superset-*`). They are third-party or live
  elsewhere, so no app-set entry exists for them.
- **`cert-manager` excluded** from the egov set — cluster-scoped infrastructure
  (CRDs, ClusterRoles) that does not fit a namespace-scoped AppProject.
- **`backbone` is thin** — only `ingress-nginx` and `redis` run there on EKS;
  Kafka/Elasticsearch live in `kafka-kraft`/`es-upgrade`, outside this scope.
- **`playground` is a duplicate top-level key** in `unified-dev.yaml`. Pre-existing,
  not introduced here, but the second block silently wins.
