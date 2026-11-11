# Kargo Promotions - Onboard a New Service or Project

<sub>[Kargo Promotions](README.md) - Onboarding</sub>

## Onboard a service into an existing project

**Before you start**

- [ ] The chart is published in `https://helm.digit.org` (see [Helm Packaging & Releasing](<../3. Helm Packaging & Releasing/>)).
- [ ] At least one image tag matching the project's tag filter exists, plus `<service>-db` if the service migrates a database (see [Code Build](<../2. Code Build/>)).
- [ ] You know the service's values (replicas, ingress, env overrides).

**Steps**

1. Add the service to `deploy-as-code/helm/charts/kargo/config/projects/<project>.yaml` under `services:`:

   ```yaml
   - name: <service>
     chart: <service>
     dbMigration: true                 # only if a <service>-db image exists
     freightCreationPolicy: Manual
     imageSelectionStrategy: NewestBuild
     cacheByTag: true
     discoveryLimit: 20
     interval: 5m0s
     # chartRepo: https://helm.digit.org/digit3/health   # only if not the project default
     # allowTags: '^<branch-prefix>-.*[0-9a-f]{7,}$'       # only if its tags differ
   ```

2. Add the service's values to each stage's env file, in a section named after the chart. Do **not** add `chart-version` or image tags - Kargo owns those keys.
3. Raise one pull request. After merge, the Warehouse and Stage appear (the pipeline Application is `kargo-<project>`).
4. Confirm the Warehouse is Ready and lists image tags and chart versions.
5. Assemble Freight and promote (see [access-and-use.md](access-and-use.md)).

### Tag filters

The registry holds mainline builds, branch builds, and per-architecture children. Only tags matching the filter become Freight. Anchor patterns on the trailing commit hash so `-amd64` / `-arm64` children never match:

```yaml
allowTags: '^(master|release)-.*[0-9a-f]{7,}$'   # project default
services:
  - name: <service>
    allowTags: '^studio-.*-[0-9]{3,}$'           # replaces the default for this service
    extraAllowTags: '^<branch>-.*[0-9a-f]{7,}$'  # appended with | for an extra family
```

A Warehouse that finds nothing is **Not Ready: "No references discovered"** - the filter matches no existing tag, or the chart is not published.

### Chart-only services

A chart that ships no image of its own (a module's config chart, or a third-party chart whose image the chart fixes) sets `image: false`. Its Freight carries only a chart version.

## Onboard a new project (module)

1. Create `config/projects/<project>.yaml` from the [project template](../Templates/kargo/project-config.yaml). Set:
   - `project`, `registry`, `chartRepo`, `allowTags`, `envFileWrite: merge`;
   - a unique `argocdAppPrefix`;
   - `git.repoURL`;
   - `stages` (name, branch, env file, `autoPromotion: false`);
   - `masterOnlyStages` (`[]` for a single standalone stage, else the production-like stages);
   - `teams` for access (see [access-and-use.md](access-and-use.md#who-can-do-what));
   - `verify.enabled` (`false` until a read-only kubeconfig Secret exists for the cluster).
2. Add the project to the pipelines ApplicationSet (`deploy-as-code/helm/charts/argo-cd/kargo/kargo-app-set-pipelines.yaml`):

   ```yaml
   elements:
     - name: <project>     # = config basename = project namespace
       branch: <env-branch>
   ```

3. Create the env file per stage (see [Argo CD onboarding](<../5. Argo CD/onboarding-a-service.md>)).
4. Provide credentials in the project namespace: image pull and git push (see [maintenance.md](maintenance.md#credentials)).
5. Set up the Argo CD side (AppProject, config Application, Applications) - see [Argo CD](<../5. Argo CD/onboarding-a-service.md>).
6. Merge, then verify: `kargo-<project>` is Synced and each Warehouse is Ready (or waiting only for a first matching build).

## Field reference

See the [Kargo field reference](maintenance.md#field-reference) in maintenance for the full list of project, service, and stage fields.
