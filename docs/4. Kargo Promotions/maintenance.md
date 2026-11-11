# Kargo Promotions - Maintenance

<sub>[Kargo Promotions](README.md) - Maintenance</sub>

## Guardrails

These are the rules every change to a pipeline follows. **MUST** and **MUST NOT** are mandatory; **SHOULD** is the default and departing from it needs a reason in the pull request.

- Kargo objects **MUST** come from the project config in git, never `kubectl apply` by hand.
- `autoPromotion` **MUST** stay `false`. Every promotion is a deliberate action.
- `envFileWrite` **SHOULD** be `merge`. The older `update` mode requires every key to be seeded first and fails with "key path not found" otherwise.
- In a promotion chain, `masterOnlyStages` **MUST** keep the production-like stages. It rejects any non-`master-*` image loudly, before anything is written, with no per-service exemptions. A single standalone stage uses `masterOnlyStages: []`.
- The chart version in a Freight **MUST** stay published while any environment uses it. Unpublishing it breaks Argo CD's render (see [Argo CD troubleshooting](<../5. Argo CD/maintenance.md#troubleshooting>)).
- Tag filters **SHOULD** anchor on the trailing commit hash so `-amd64` / `-arm64` children never become Freight.

## Credentials

Each project namespace holds the credentials its pipeline uses. These are SOPS-encrypted in git and decrypted into the cluster (see [Argo CD - secrets](<../5. Argo CD/maintenance.md#secrets-and-sops>)).

| Secret | Used for |
|---|---|
| Image pull credentials | Reading tags from the registry |
| Git credentials (or GitHub App) | Pushing promotion commits to the env branch |

Rotate by re-encrypting the secret and raising a pull request. Never commit a plaintext credential.

## Promotion pushes and branch protection

Promotion pushes a commit straight to the environment branch. Two setups:

- **No branch protection yet** - the push uses ordinary git credentials. Simplest while an environment is being brought up.
- **Protected branch** - add the promotion identity (a GitHub App) to the branch protection rule's bypass list, so promotion commits are accepted while human pushes still go through pull request. Add the App to the bypass list in the same change that turns protection on, or promotions start failing.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Warehouse Not Ready: "No references discovered" | No tag matches the filter, or the chart is not published | Check the registry and the regex; add `extraAllowTags`; confirm the chart is published |
| Freight shows an unexpected "newest" tag | Images report identical build dates | Choose the tag explicitly when assembling |
| Promotion rejected: "only master-* images may be promoted" | Non-mainline image into a `masterOnlyStages` stage | Promote a `master-*` build |
| Promotion fails: "key path not found" | `envFileWrite: update` and the key is not seeded | Seed the key by pull request, or switch the project to `merge` |
| Promotion push rejected | Protected branch, promotion identity not on the bypass list | Add the GitHub App to the branch protection bypass list |
| Promotion succeeded, nothing deployed | No Application for the service, or the commit did not reach the branch | Confirm the service is in the config / ApplicationSet; confirm the commit is on the branch; check Argo CD |
| Warehouse shows OutOfSync on `strictSemvers` | CRD default differs from the rendered manifest | Already handled by the pipeline ApplicationSet `ignoreDifferences`; refresh the app |

## Retire a service or project

1. Remove the service from the project config (or the project from the pipelines ApplicationSet) and raise a pull request.
2. After merge, the Warehouse and Stage stop being rendered. Because Argo CD uses `prune: false`, delete the leftover Kargo objects by hand once the pull request has merged.
3. Clean up the deployed workload on the Argo CD side (see [Argo CD maintenance](<../5. Argo CD/maintenance.md>)).

## Field reference

### Project (`kargo:`)

| Field | Meaning |
|---|---|
| `project` | Project name (= namespace on the Kargo cluster) |
| `registry` | Image registry prefix (for example `docker.io/egovio`) |
| `chartRepo` | Default Helm repository |
| `chartVersionKey` | Env-file key for the chart version (default `chart-version`) |
| `allowTags` | Default tag filter |
| `masterOnlyStages` | Stages accepting only `master-*` images (`[]` for a single stage) |
| `envFileWrite` | `merge` (recommended) or `update` |
| `argocdAppPrefix` | Prefix of the Argo CD Application names |
| `git.repoURL` | Repository holding the env files |
| `verify.enabled` | Post-promotion verification (needs a read-only kubeconfig Secret) |
| `stages`, `teams`, `services` | See below |

### Service (`services[]`)

| Field | Meaning |
|---|---|
| `name` | Warehouse name, Stage prefix, default env-file section |
| `chart`, `chartRepo`, `chartSemver` | Chart name; per-service repo and version constraint |
| `image` | `false` for chart-only services |
| `repo` | Image repository name if different from `name` |
| `valuesKey` | Env-file section to write (default `name`) |
| `dbMigration` | Also write the tag for the `<service>-db` migration image |
| `allowTags`, `extraAllowTags` | Replace / extend the tag filter |
| `freightCreationPolicy`, `interval`, `cacheByTag`, `discoveryLimit`, `imageSelectionStrategy` | Discovery behaviour |

### Stage (`stages[]`)

| Field | Meaning |
|---|---|
| `name` | Environment; Stages are `<service>-<name>` |
| `from` | Upstream stage (omit on the first) |
| `branch`, `envFile` | Where the promotion writes |
| `autoPromotion` | Keep `false` |
| `color` | UI colour |
