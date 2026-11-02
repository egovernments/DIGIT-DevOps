# Operations Runbook

<sub>**Deployment Guide** · Part 8 of 11 · [Contents](README.md) · Next: [SOP and Guardrails](09-sop-and-guardrails.md)</sub>

Step-by-step procedures for routine operations. Each assumes the rules in [09 SOP and Guardrails](09-sop-and-guardrails.md).

## Contents

- [Release a service](#release-a-service)
- [Roll back a release](#roll-back-a-release)
- [Release without Kargo](#release-without-kargo)
- [Check a deployment after a change](#check-a-deployment-after-a-change)
- [Refresh an Application or ApplicationSet](#refresh-an-application-or-applicationset)
- [Move Applications to another ApplicationSet](#move-applications-to-another-applicationset)
- [Retire an Application, ApplicationSet or AppProject](#retire-an-application-applicationset-or-appproject)
- [Add an environment](#add-an-environment)
- [Rotate a secret](#rotate-a-secret)
- [Copy reference data between environments](#copy-reference-data-between-environments)

## Release a service

1. **Kargo UI → project → Warehouse `<service>`:** confirm the image tag and chart version you intend are listed.
2. **Assemble Freight:** choose the tag and the chart version explicitly.
3. **Promote to dev:** select the Freight on Stage `<service>-dev` and promote.
4. **Confirm the commit** `kargo: promote <service> to dev` on `<dev-branch>`.
5. **Check the deployment** ([below](#check-a-deployment-after-a-change)).
6. **Promote to qa, then uat,** the same way, after each environment is verified. uat accepts `master-*` images only.

## Roll back a release

| Kargo + Argo CD | Argo CD only |
|---|---|
| Promote the previous Freight to the affected stage | Revert the version-change commit by pull request |

If the previous Freight cannot be promoted (for example Kargo is unavailable), revert the promotion commit by pull request and note it on the change record, so the next promotion is not misread.

A rollback **does not undo database migrations**. If the new release migrated a schema, agree the rollback with the service owner first.

## Release without Kargo

1. Pull request to `<dev-branch>` changing `<service>.chart-version` and `<service>.image.tag` (and `initContainers.dbMigration.image.tag`).
2. After merge, [check the deployment](#check-a-deployment-after-a-change).
3. Repeat on `<qa-branch>`, then `<uat-branch>` (mainline builds only).

## Check a deployment after a change

```sh
# the Application picked up the commit, and its state
kubectl -n argocd get app <app> -o jsonpath='{.status.sync.revision} {.status.sync.status}/{.status.health.status}{"\n"}'

# why a sync failed
kubectl -n argocd get app <app> -o jsonpath='{.status.operationState.message}{"\n"}'

# pods: init containers first, then the application container
kubectl -n <namespace> get pods -l app=<service>
kubectl -n <namespace> logs <pod> -c <init-container>
kubectl -n <namespace> logs <pod> --previous

# the running image matches the promoted tag
kubectl -n <namespace> get deploy <service> -o jsonpath='{.spec.template.spec.containers[0].image}{"\n"}'
```

**Done when:** Synced at the new revision, Healthy, and the image tag and chart version match the release.

## Refresh an Application or ApplicationSet

```sh
# normal refresh: re-read git
kubectl -n argocd annotate app <app> argocd.argoproj.io/refresh=normal --overwrite

# re-run an ApplicationSet (for example after its AppProject was created)
kubectl -n argocd annotate applicationset <appset> argocd.argoproj.io/application-set-refresh=true --overwrite
```

Avoid hard refreshes unless they are needed. A hard refresh discards the cached render, and an Application pinned to a chart version that is no longer published then fails to render.

## Move Applications to another ApplicationSet

An Application belongs to the ApplicationSet that created it; another ApplicationSet cannot take it over.

1. Merge the new ApplicationSet. It reports "already owned by another ApplicationSet" for the existing Applications. This is expected.
2. With approval, delete the old ApplicationSet **without deleting its Applications**:

   ```sh
   kubectl -n argocd delete applicationset <old-appset> --cascade=orphan
   ```

3. Confirm that the new ApplicationSet adopted the Applications (same names, new owner) and they stay Synced and Healthy. Workloads are not restarted.
4. Remove the old ApplicationSet's file from git, if that has not been done already.

## Retire an Application, ApplicationSet or AppProject

The bootstrap app does not prune, so removal is two steps:

1. **Remove the manifest** (or the ApplicationSet element) by pull request.
2. **With approval, delete the object.** Use `--cascade=orphan` to keep the workloads, or a normal delete to remove them as well. Record which one was chosen.

## Add an environment

1. Create `<new-env-branch>` from an existing environment branch, and protect it.
2. Create the env files `<module>-<new-env>.yaml` and the encrypted `-secrets.yaml`, with that environment's values and its own `.sops.yaml` rule and key.
3. Copy `<argocd-dir>/<env>/` to `<argocd-dir>/<new-env>/`, and adjust branch names, stage names (Kargo-managed ApplicationSets select the stage by name) and AppProjects.
4. Install Argo CD on the new cluster and apply its bootstrap Application.
5. (Kargo) Add the stage to each project config (`from:` the previous stage).

## Rotate a secret

1. Rotate at the source (database, registry, provider).
2. `sops <environments-dir>/<module>-<env>-secrets.yaml`, update the value, pull request.
3. After merge, check the config Application synced; restart the workloads that read the secret only at start-up.

## Copy reference data between environments

For master data or configuration rows that must match another environment:

1. **Read-only on the source.** Never write to the source.
2. **Stream source to target** without saving the data locally.
3. **Load in one transaction** into a staging table, insert with `ON CONFLICT DO NOTHING`, and **roll back if any row would be skipped**.
4. **Dry run first** (end with `ROLLBACK`), then run for real.
5. **Verify on both sides** with row counts and a hash over the rows (for example `md5(string_agg(md5(row::text), '' ORDER BY <key>))`).
6. Record what was copied, from where, and the verification result.

---

<sub>← Previous: [Access Control](07-access-control.md) &nbsp;|&nbsp; [Contents](README.md) &nbsp;|&nbsp; Next: [SOP and Guardrails](09-sop-and-guardrails.md) →</sub>
