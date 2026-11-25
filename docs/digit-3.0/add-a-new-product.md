# Runbook: add a new product (`<product>-3.0`)

Use this to onboard a whole new DIGIT 3.0 product, for example `hcm-3.0`, `cms-3.0`, or
`studio-3.0`. Follow the steps in order. Each step says exactly which file to touch and how to
check it worked. Do not skip the checks.

Before you start, read [README.md](README.md) (especially the Golden rules) and
[structure.md](structure.md).

> Throughout this page, replace `<product>` with the readable product name (for example `hcm`),
> `<module>` with the dotted module name (`hcm-3.0`), and `<ns>` with the dashed namespace
> (`hcm-3-0`). Example mapping: product `hcm` -> module `hcm-3.0` -> namespace `hcm-3-0`.

## Before you begin - confirm these facts

Write down the answers; every step below uses them.

1. **Product name and names.** `<product>`, `<module>` (`<product>-3.0`), `<ns>` (`<product>-3-0`).
2. **Published chart repo.** Confirm the module's charts exist at
   `https://helm.digit.org/digit3/<module-repo>` and open its `index.yaml` in a browser to see
   the chart names and newest versions. If the charts are not published yet, stop: they must be
   released first (in the `helm-charts` repository). Onboarding here only references published
   charts.
3. **Public hostname.** Use `<product>-3.unified-dev.digit.org`. This resolves automatically
   through the existing `*.unified-dev.digit.org` wildcard DNS - no DNS ticket is needed. Confirm
   with `dig +short <product>-3.unified-dev.digit.org` (it should return the ingress load-balancer
   IP, the same as any other `*.unified-dev.digit.org` host).
4. **Backbone.** Decide whether the product reuses the existing backbone (postgresql, vault in
   `backbone-3-0`) or needs its own database/vault. Reusing the shared backbone is simpler; a
   dedicated backbone is a second module you onboard the same way.

> **Guardrail:** if you cannot answer all four, do not start. Guessing a chart repo, a version, or
> a hostname leads to a broken deploy that is hard to unwind.

## Step 1 - Create the Kargo project file

Copy `charts/kargo/config/projects/core-3-0.yaml` to
`charts/kargo/config/projects/<ns>.yaml` and adapt it. The core file is thoroughly commented;
keep those comments as your guide. Set at least:

```yaml
kargo:
  project: <ns>                      # e.g. hcm-3-0
  registry: docker.io/egovio
  argocdAppPrefix: digit3-           # keep digit3- so app names stay unique across modules
  argocd:
    project: <ns>-project            # e.g. hcm-3-0-project
    namespace: <ns>
    namespaces: [<ns>]               # add backbone-3-0 too only if this module renders secrets there
    layout: common
  envFileWrite: merge
  git:
    repoURL: https://github.com/egovernments/DIGIT-DevOps.git
  chartRepo: https://helm.digit.org/digit3/<module-repo>
  verify:
    enabled: true                    # dev only; see the comment in core-3-0.yaml
    namespace: <ns>
  services:
    - name: <first-service>
      chart: <first-service>
      dbMigration: true              # true if the service has a <service>-db migration image
      freightCreationPolicy: Manual
      imageSelectionStrategy: NewestBuild
      cacheByTag: true
      discoveryLimit: 20
      interval: 5m0s
    # ... one block per service ...
  stages:
    - name: dev
      branch: unified-dev
      envFile: deploy-as-code/helm/environments/digit-3.0/<module>.yaml
      autoPromotion: false
      verifyKubeconfigSecret: verify-kubeconfig-dev
    - name: qa
      from: dev
      branch: unified-qa
      envFile: deploy-as-code/helm/environments/digit-3.0/<module>.yaml
      autoPromotion: false
    - name: uat
      from: qa
      branch: unified-uat
      envFile: deploy-as-code/helm/environments/digit-3.0/<module>.yaml
      autoPromotion: false
  teams:
    - name: devops
      role: admin
      groups: [egovernments:micro-service-devops]
```

> **Guardrail:** every namespace you list under `argocd.namespaces` must also appear as a
> destination in the AppProject you create in Step 3, or Kargo's render fails on purpose.

## Step 2 - Register the Kargo project

Edit `charts/argo-cd/unified-dev/kargo/kargo-app-set-pipelines.yaml` and add your project to the
`elements` list:

```yaml
          - name: <ns>
            branch: unified-dev
```

Then edit `charts/argo-cd/unified-dev/kargo/kargo-app-project.yaml` and add your namespace to its
destinations so Kargo is allowed to manage it:

```yaml
    - namespace: <ns>
      server: https://kubernetes.default.svc
```

> **Guardrail:** the project file from Step 1 does nothing until it is listed here. This is the
> most common "why is nothing happening" mistake.

## Step 3 - Create the Argo CD AppProject

Create `charts/argo-cd/unified-dev/digit-3.0/<module>/<ns>-app-project.yaml`. Copy
`core-3.0/core-3-0-app-project.yaml` and adapt:

```yaml
apiVersion: argoproj.io/v1alpha1
kind: AppProject
metadata:
  name: <ns>-project
  namespace: argocd
spec:
  description: DIGIT 3.0 <product> module (<module>) for the Azure AKS unified-dev environment
  sourceRepos:
    - https://github.com/egovernments/DIGIT-DevOps.git     # values
    - https://helm.digit.org/digit3/<module-repo>          # service charts
    - https://helm.digit.org/digit3/cluster-configs        # module ConfigMaps/Secrets
  destinations:
    - namespace: '<ns>'
      server: https://kubernetes.default.svc
    # add backbone-3-0 only if this module renders secrets there
```

> **Guardrail:** do not add `clusterResourceWhitelist` unless a chart genuinely needs a
> cluster-scoped object. Leaving it empty is what stops a module from reaching outside its
> namespace.

## Step 4 - Create the values files

Create `environments/digit-3.0/<module>.yaml`:

```yaml
global:
  namespace: <ns>
  mode: prod
  domain: <product>-3.unified-dev.digit.org
# one top-level section per service; chart-version is filled by the first promotion,
# or seed it by hand from the published index to bootstrap:
<first-service>:
  chart-version: "<newest-from-index>"
  ingress:
    enabled: true
cluster-configs:
  chart-version: "<newest-cluster-configs-version>"
  # which ConfigMaps/Secrets to render and into which namespace(s)
```

Create `environments/digit-3.0/<module>-secrets.yaml` and add a matching rule to the
repository's `.sops.yaml` so this path is encrypted with the right key (copy the existing
`environments/digit-3.0/.*-secrets.yaml` rule if one already covers it). Put secret values in
through SOPS only - never commit plaintext.

> **Guardrail (Rule 5):** set `global.mode: prod`. In `prod` every service uses the released
> image baked into its chart. Use `dev` only to test an unreleased build.

## Step 5 - Register the namespace cluster-wide

Edit `environments/unified-dev.yaml`:

1. Add `<ns>` to the cluster-configs **namespaces** list (the `values: [ ... ]` line) so the
   namespace is created and labelled for Kargo.
2. Add `<ns>` to the Kargo **projects** list.

> **Guardrail (Rule 4):** these two entries are the *only* things about the module that belong in
> `unified-dev.yaml`. Every other setting goes in the module's own values file.

## Step 6 - Validate locally (before the pull request)

Run these from the repository root. All must pass.

```bash
# 1. YAML is valid
python3 -c "import yaml,sys; [list(yaml.safe_load_all(open(f))) for f in sys.argv[1:]]" \
  deploy-as-code/helm/environments/digit-3.0/<module>.yaml \
  deploy-as-code/helm/charts/kargo/config/projects/<ns>.yaml \
  deploy-as-code/helm/charts/argo-cd/unified-dev/digit-3.0/<module>/<ns>-app-project.yaml

# 2. No leftover copied names from the file you adapted (should print nothing)
grep -rn "core-3-0\|core-3.0" \
  deploy-as-code/helm/charts/kargo/config/projects/<ns>.yaml \
  deploy-as-code/helm/charts/argo-cd/unified-dev/digit-3.0/<module>/

# 3. The hostname resolves
dig +short <product>-3.unified-dev.digit.org
```

> **Guardrail:** if check 2 prints anything, you copied a name you forgot to change. Fix it before
> opening the pull request.

## Step 7 - Open a pull request

Commit only the files you created or edited (list them explicitly; never stage everything blindly).
Open a pull request against `unified-dev`. Describe what module you are adding and the four facts
from "Before you begin". **Stop here. A person reviews and merges.** Do not merge your own pull
request.

## Step 8 - After the merge, confirm it came up

Once merged, Argo CD and Kargo reconcile. Confirm (against the `unified-dev` cluster):

- The Kargo project `<ns>` shows **Synced and ready**.
- The namespace `<ns>` exists and is **Active**.
- The AppProject `<ns>-project` exists.
- After the first promotion (see [operate-argocd-and-kargo.md](operate-argocd-and-kargo.md)),
  the `digit3-<service>` Applications appear and go **Synced / Healthy**, and the service's route
  on `https://<product>-3.unified-dev.digit.org/...` answers (a protected route returns 401, not
  404 or 502).

If something is stuck, go to [operate-argocd-and-kargo.md](operate-argocd-and-kargo.md) -> the
troubleshooting section.

## Quick checklist

- [ ] Kargo project file `config/projects/<ns>.yaml`
- [ ] Registered in `kargo-app-set-pipelines.yaml` and `kargo-app-project.yaml`
- [ ] AppProject `digit-3.0/<module>/<ns>-app-project.yaml`
- [ ] Values file `environments/digit-3.0/<module>.yaml` with `mode: prod` and the hostname
- [ ] Secrets file `<module>-secrets.yaml` + `.sops.yaml` rule
- [ ] Namespace + Kargo project registered in `unified-dev.yaml`
- [ ] Local validation passed (YAML, no leftover names, DNS resolves)
- [ ] Pull request opened; a person merges
- [ ] Post-merge checks green
