# 09 SOP and Guardrails

The standard operating procedure for every change made through Kargo, Argo CD, or both. **MUST** and **MUST NOT** are mandatory. **SHOULD** is the default; departing from it needs a stated reason in the pull request. When a situation is not covered, apply the principles below and stop for review rather than improvising.

## Contents

- [Principles](#principles)
- [Ownership](#ownership)
- [Repository and branches](#repository-and-branches)
- [Kargo](#kargo)
- [Argo CD](#argo-cd)
- [Charts and values](#charts-and-values)
- [Databases and migrations](#databases-and-migrations)
- [Secrets and access](#secrets-and-access)
- [Changes outside git](#changes-outside-git)
- [Before raising a pull request](#before-raising-a-pull-request)
- [After merge](#after-merge)
- [Approval levels](#approval-levels)
- [Prohibited actions](#prohibited-actions)
- [Recovery](#recovery)
- [Argo CD only model](#argo-cd-only-model)

## Principles

1. **Git is the source of truth.** An environment is what its branch says. Anything else is drift and will be reverted or lost.
2. **Every change is a reviewed pull request.** The only other writer is a Kargo promotion, and only for the keys it owns.
3. **One owner per thing.** Each env-file key, Kubernetes object and Application has exactly one writer.
4. **Smallest scope that works.** Prefer a per-application override to a change of something shared.
5. **Prove before merge, verify after.** Render and compare before; check sync, health and logs after.
6. **No hidden side effects.** Every effect beyond the stated purpose is shown in the pull request, or the change is split.
7. **Secrets are never visible.** Not in plaintext in git, logs, pull requests or messages.
8. **Stop on surprise.** An unexpected diff, error or denial stops the change until it is understood. Do not work around it.

## Ownership

| Item | Written by |
|---|---|
| `<service>.chart-version`, `<service>.image.tag`, `<service>.initContainers.dbMigration.image.tag` | **Kargo promotions** (pull requests in the Argo CD only model) |
| All other env-file values | Engineers, by pull request |
| Secrets files | Engineers, with `sops`, by pull request |
| Kargo project configs, ApplicationSets, AppProjects | Engineers, by pull request |
| Objects of managed Applications on the cluster | **Argo CD** |
| Freight | The team granted `manageFreight` |
| Promotions | Promoters of that stage |

## Repository and branches

- **MUST** change an environment only by pull request to its branch.
- **MUST** start from the latest remote base, with one purpose per pull request.
- **MUST NOT** force-push or rewrite environment branches.
- **MUST** confirm after merge that the merged result contains every commit of the pull request. A commit pushed while the merge was happening may be missing; raise it again rather than assume.
- **SHOULD** keep each module's values in its own env file.

## Kargo

**Warehouses and tags**

- **MUST** anchor tag filters on the trailing commit hash (`…[0-9a-f]{7,}$`).
- **MUST** widen the filter for one service with `extraAllowTags`, never by loosening the project-wide `allowTags`.
- **MUST NOT** create or edit Kargo objects by hand; change the project config.
- **SHOULD** keep `freightCreationPolicy: Manual`.

**Freight**

- **MUST** choose the image tag and chart version explicitly.
- **MUST** confirm that the image (and `<service>-db`, if used) exists for the tag, and that the chart version is published.

**Promotion**

- **MUST** promote in order dev → qa → uat, with `autoPromotion: false`.
- **MUST** promote only `master-*` builds to uat. **MUST NOT** add exemptions to this rule for any service.
- **MUST** verify each promotion ([After merge](#after-merge)) before the next.
- **MUST** use `envFileWrite: merge` for new projects.
- **MUST NOT** hand-edit a Kargo-owned key, except as in [Recovery](#recovery).

**Projects and access**

- **MUST** give each project a unique `argocdAppPrefix`.
- **MUST** grant access only through the project's `teams:`; grant `manageFreight` only to the team that assembles releases.

## Argo CD

**AppProjects**

- **MUST** list every repository used, including `https://helm.digit.org`, in `sourceRepos`.
- **MUST** list destination namespaces explicitly. **MUST NOT** use `namespace: '*'` for application projects.
- **MUST** keep `clusterResourceWhitelist` empty unless a chart needs a specific kind; name it and the reason in a comment.
- **MUST** add a new namespace to the AppProject (and to `argocd.namespaces` for Kargo-managed projects) in the same pull request as its first Application.

**ApplicationSets and Applications**

- **MUST** keep exactly one ApplicationSet generating each Application name.
- **MUST** move Applications between ApplicationSets only by the procedure in [08](08-operations-runbook.md#move-applications-to-another-applicationset).
- **MUST** plan the manual removal of retired objects; removing a file does not delete the object.
- **MUST** use the standard sync policy ([05](05-argocd-guide.md#how-deployments-are-managed)). **MUST NOT** enable pruning without reviewing what it would delete.
- **MUST** set `helm.skipCrds: true` for charts that ship CRDs, when the AppProject allows no cluster-scoped kinds.
- **SHOULD** use an existing values layout. Add a new layout only for a chart none of them can serve.
- **SHOULD NOT** hard-refresh without need.

**Shared configuration**

- **MUST NOT** change shared objects (a namespace's shared ConfigMaps, a library chart, the cluster-wide configuration) without listing every consumer and the effect on each in the pull request.
- **SHOULD** fix one application's problem with an override in that application's values.
- **MUST**, when changing a library chart or a shared template, render the unaffected applications before and after and show they are byte-identical.

## Charts and values

- **MUST** key a service's env-file section by its chart name.
- **MUST** restate the whole list when overriding a list (Helm replaces lists).
- **MUST** check rendered Deployments for duplicate env var names. Server-side apply rejects the whole Deployment.
- **MUST** check which image tag the chart actually uses (image-tag mode).
- **MUST** take hostnames from configuration (shared ConfigMaps), never hard-code them in charts.
- **MUST NOT** delete a published chart version that an environment pins.
- **MUST** emit one YAML document per object in templates that loop over namespaces.

## Databases and migrations

- **MUST** give each module its own schema when modules share a database, using a schema-scoped connection URL.
- **MUST** run an application and its migration image from the same build tag.
- **MUST NOT** repair migration history, drop tables or edit history tables without explicit approval and a written reason. Prefer correcting the configuration.
- **MUST** copy data between environments only by the procedure in [08](08-operations-runbook.md#copy-reference-data-between-environments).
- **MUST NOT** give administrator logins as read access; use a read-only role.

## Secrets and access

- **MUST** create the `.sops.yaml` rule before the secrets file; edit only with `sops`.
- **MUST NOT** commit, paste or print decrypted values.
- **MUST NOT** reuse one environment's cluster credentials in another environment.
- **MUST** grant the least privilege needed. Debugging roles never include Secret read.
- **MUST** record every access grant: what, for whom, how to revoke.
- **MUST** keep local credential files readable only by their owner, and delete them once stored properly.

## Changes outside git

Some actions cannot be pull requests: database roles, access tokens, orphan deletes, data copies.

- **MUST** be the exception, with a stated reason.
- **MUST** be reviewed beforehand: show a server-side dry run or the exact command.
- **MUST** be recorded: what, where, how to undo.
- **MUST NOT** target anything Argo CD manages; self-heal reverts it.
- **SHOULD** use read-only checks freely: listing objects, `kubectl auth can-i`, rendering, read-only queries.

## Before raising a pull request

- [ ] **Changed charts render** with the real env file:
  ```sh
  helm template <service> <chart> --version <x.y.z> -n <namespace> -f <env-file>
  ```
- [ ] **Shared changes compared before and after:** unrelated renders are byte-identical.
- [ ] **No duplicate env var names** in rendered Deployments.
- [ ] **Every referenced ConfigMap/Secret key exists** in the target namespace, or is added in the same pull request.
- [ ] **Every image tag** (application and migration) and **chart version** exists.
- [ ] **Ingress paths do not clash** on the same host.
- [ ] **New namespaces** are in the AppProject (and `argocd.namespaces`).
- [ ] (Kargo) **The project config renders**, and unrelated projects are unchanged.
- [ ] **Argo CD manifests pass** `kubectl apply --dry-run=server -f <file>`.
- [ ] **Secrets files are encrypted** and match a `.sops.yaml` rule.
- [ ] **The description** states purpose, effect, verification and any manual follow-up.

## After merge

- [ ] **The merged commit** contains every intended commit.
- [ ] **The bootstrap app or ApplicationSet** is on the merged revision.
- [ ] **Each affected Application is Synced.** Read the sync result before acting on any failure.
- [ ] **Each affected Application is Healthy.** Otherwise check init containers, then container logs.
- [ ] **For releases:** the running image tag and chart version match the release.
- [ ] **Any remaining failure** is recorded with its owner.

## Approval levels

| Change | Approval |
|---|---|
| Promote to dev | Dev promoter |
| Promote to qa / uat | Promoter of that stage; uat mainline only |
| Add a service, change one service's values | One reviewer |
| New project, module, AppProject, namespace or values layout | Platform owner |
| Shared configuration, library chart, sync policy | Platform owner, with before/after render comparison |
| Access grants, database roles, data copies, orphan deletes, any change outside git | Environment owner, recorded |
| Migration-history repair, data deletion | Service owner and environment owner |

## Prohibited actions

- Commit directly to, force-push or rewrite an environment branch.
- Hand-edit Kargo-owned keys (outside [Recovery](#recovery) and the Argo CD only model).
- Promote non-mainline builds to uat, or add exemptions.
- Create or edit Kargo objects or Argo CD-managed objects on a cluster by hand.
- Let two ApplicationSets generate one Application, or delete an ApplicationSet without `--cascade=orphan` when its Applications must stay.
- Use `namespace: '*'` or broad cluster-scoped kinds in application AppProjects.
- Delete a published chart version in use.
- Commit, print or paste decrypted secrets; reuse credentials across environments.
- Give administrator database logins as read access, or Secret read in debugging roles.
- Repair migration history or delete data without approval.

## Recovery

| Situation | Action |
|---|---|
| A release broke an environment | Promote the previous Freight. If Kargo is unavailable, revert the promotion commit by pull request and record it. |
| A configuration change broke an environment | Revert the pull request |
| Application OutOfSync with a sync error | Read the error; fix in git ([10](10-troubleshooting.md)) |
| ApplicationSet reports a missing project after the project was created | Refresh the ApplicationSet |
| "Already owned by another ApplicationSet" | Hand over ownership ([08](08-operations-runbook.md#move-applications-to-another-applicationset)) |
| Old pod remains while a rollout cannot complete | Fix the new pods; do not delete the old ReplicaSet to "unblock" |
| Migration checksum mismatch | Stop. Compare both builds' migrations and decide with the service owner. |
| Secret exposed | Rotate at the source, update by pull request, record the incident |

## Argo CD only model

The rules above apply unchanged, with these differences:

- Engineers write `chart-version`, `image.tag` and the migration tag by pull request, one environment branch at a time, in order dev → qa → uat, with mainline builds only in uat.
- Applications come from the module's hand-listed ApplicationSet. Add an element only when its version is in the env file, or use the selector ([05](05-argocd-guide.md#hand-listed-applicationset-argo-cd-only)).
