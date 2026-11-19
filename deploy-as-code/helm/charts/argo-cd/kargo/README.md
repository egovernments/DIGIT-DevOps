# Kargo on digit-lts

Kargo (akuity OSS, chart `1.11.4`) on the **digit-lts** AKS cluster, installed and driven
by the cluster's Argo CD. UI at **https://kargo-latest.digit.org**. One control-plane
instance serves every project/stage on this cluster.

The root app (`charts/argo-cd/bootstrap/digit-lts-bootstrap.yaml`) syncs this directory
recursively, so merging to the `digit-lts` branch is enough; there is no manual apply.

## Files

| File | What it creates |
|---|---|
| `kargo-app-project.yaml` | AppProject `kargo-project` (control-plane + pipeline namespaces, CRDs/webhooks/cluster-RBAC whitelist) |
| `kargo-application.yaml` | The control plane: OCI chart `ghcr.io/akuity/kargo-charts` `1.11.4` + values from `charts/kargo/config/control-plane.yaml` |
| `kargo-dex-application.yaml` | Standalone Dex (chart `dex` `0.24.1`) for SSO, with **persistent** (`storage: kubernetes`) signing keys. See **SSO / Dex** below |
| `kargo-app-set-pipelines.yaml` | One `kargo-<project>` Application per element, each rendering `charts/kargo` + `config/projects/<project>.yaml` into that project's namespace |
| `argo-rollouts-application.yaml` | Argo Rollouts (only a prerequisite for Kargo's deploy-state verification) |

Pipeline chart + per-project configs: `deploy-as-code/helm/charts/kargo/`
(`config/control-plane.yaml`, `config/projects/<project>.yaml`). Credentials and the
`kargo-api` admin Secret are rendered by the **cluster-configs** chart, not here.

## Model

- **Project = module** (its own namespace, e.g. `crest-lts`), **Stage = environment**.
  This cluster is standalone, so each service has a single stage, `digit-lts`, taking
  Freight straight from its Warehouse (no dev -> qa -> uat chain).
- **Freight** = image tag (`docker.io/egovio/<svc>`) + packaged chart version
  (`helm.digit.org/digit3/<module>`). Assembled by hand (`freightCreationPolicy: Manual`),
  promoted by a person (`autoPromotion: false`).
- A promotion **merges** the Freight's keys into the module env file on the `digit-lts`
  branch (`<svc>.chart-version`, `<svc>.image.tag`, migration tag). The module's existing
  ApplicationSet re-reads that file (git files generator, ~60s) and Argo CD syncs. No
  `argocd-update` step is needed on this single cluster.
- Promotion commits are pushed **directly** to the protected `digit-lts` branch by the
  GitHub App (App `5118215`), which must be allowed to bypass the branch protection.

## Projects

| Project (namespace) | Module | Chart source | Services |
|---|---|---|---|
| `crest-lts` | crest | `helm.digit.org/digit3/crest` (root layout) | `crest`, `crest-ui` |

Studio is intentionally not here yet: its charts deploy from in-repo git paths, not the
published repo, so it is image-tag-only under Kargo (open design decision).

## Prerequisites (one-time)

1. **DNS**: `kargo-latest.digit.org` -> the digit-lts nginx ingress LB IP. cert-manager
   then issues `kargo-latest.digit.org-tls-certs` (ClusterIssuer `letsencrypt-prod`) on
   first sync.
2. **GitHub OAuth App** (for Dex SSO): Homepage `https://kargo-latest.digit.org`,
   callback `https://kargo-latest.digit.org/dex/callback`. Approve it in **both** the
   `egovernments` and `digitnxt` orgs (Org -> Settings -> Third-party access) so Dex can
   read each org's private team membership. Put its client ID/secret in
   `test-lts-secrets.yaml` and flip `cluster-configs.secrets.kargo.dexSecret.enabled: true`
   in `test-lts.yaml`.
3. **GitHub App `5118215`**: confirm it has write access to the repo **and** bypasses the
   `digit-lts` branch protection (promotions push commits directly).
4. **Credentials in `test-lts-secrets.yaml`** (SOPS/Azure Key Vault `digit-lts-sops-kv`
   after PR #5553, under `cluster-configs.secrets.kargo`), required before Kargo starts:
   - `imageCredentials` (egovio Docker Hub, for Warehouse tag discovery),
   - `gitCredentials` (App `5118215`: `githubAppID`, `githubAppInstallationID`,
     `githubAppPrivateKey`, `repoURL`) -- reuse the values from `unified-dev-secrets.yaml`,
   - `adminSecret.passwordHash` (bcrypt) + `adminSecret.tokenSigningKey` (random),
   - `dexSecret.clientID` / `dexSecret.clientSecret` (after step 2).

## SSO / Dex

Kargo authenticates via Dex (GitHub connector, both `egovernments` and `digitnxt` orgs;
groups claim `<org>:<team-slug>`). We run a **standalone** Dex (`kargo-dex-application.yaml`)
instead of the one Kargo's chart bundles, because the bundled Dex hardcodes
`storage: memory` and so **regenerates its signing keys on every pod restart**. A routine
AKS node-pool roll therefore gave Dex new keys while the Kargo API kept verifying tokens
against the old (cached) key set, so every SSO login failed with
`failed to verify id token signature` until the API was manually restarted.

The standalone Dex uses `storage: kubernetes` (keys persisted as `dex.coreos.com` CRDs), so
keys survive restarts and node rolls and SSO is no longer disrupted. Kargo consumes it in
BYO mode (`api.oidc.dex.byo` in `control-plane.yaml`): the API still serves `/dex` and
reaches Dex in-cluster at `https://kargo-dex.kargo.svc:5554`, trusting the self-signed cert
`kargo-dex-cert` (cert-manager, rendered by cluster-configs). The API also gets a
`wait-for-dex` init container so its OIDC key set initialises cleanly on startup. Issuer,
clients and the GitHub connector are identical to the bundled config, so all existing RBAC
is unchanged. The GitHub OAuth app and its callback (`/dex/callback`) are unchanged too.

## Add a project later

Add `config/projects/<name>.yaml`, add the matching element to
`kargo-app-set-pipelines.yaml`, add `<name>` to `kargo-project` destinations and to
`cluster-configs.secrets.kargo.projects` (so its git/image-cred Secrets are rendered).
