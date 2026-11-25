# Operating Argo CD and Kargo for DIGIT 3.0

This page explains how DIGIT 3.0 is kept running day to day: how a version actually reaches the
cluster, how to promote, how to check health, and how to diagnose the problems that actually
happen. Read [README.md](README.md) for the mental model first.

## How a change reaches the cluster (the full path)

```
1. A new image/chart version is published      (outside this repo: CI + helm-charts release)
2. Kargo's Warehouse discovers it               (re-scans every 5 minutes)
3. A person assembles Freight (image + chart)   (freightCreationPolicy: Manual)
4. A person promotes Freight to dev             (autoPromotion: false)
5. Kargo writes chart-version + image.tag into  environments/digit-3.0/<module>.yaml  (merge)
6. Argo CD sees the values file changed         (GitHub webhook -> immediate refresh)
7. Argo CD syncs the digit3-<service> app        (installs the chart with the new values)
8. Pods roll in namespace <module>-3-0
9. (dev only) Kargo verifies the Deployment runs the promoted tag and is healthy
10. A person promotes dev -> qa, then qa -> uat  (linear; qa only from dev, uat only from qa)
```

Nothing in steps 3, 4, or 10 happens on its own. Discovery (step 2) and syncing (steps 6-8) are
automatic; choosing and promoting versions is always a human decision.

## Promoting a version (the normal task)

1. Open the Kargo UI for the module's project (`core-3-0`, `backbone-3-0`, your module).
2. In the service's Warehouse, pick the Freight you want (an image tag + chart version bundled
   together).
3. Promote it to **dev**. Kargo opens a change to the values file on the `unified-dev` branch.
4. Wait for Argo CD to sync and for the dev verification to pass (the Deployment must run the
   promoted tag and be healthy).
5. Promote **dev -> qa**, then **qa -> uat**, each as a deliberate step. Promotion is linear: qa
   can only take what is in dev, uat only what is in qa.

Notes:
- `uat` takes `master-*` release builds only; `flyway-branch-*` builds reach dev and qa only.
- The dev verification is enabled only where services actually run. A stage with no services
  deployed yet has verification off, because a check there could never pass.

## Checking health

Point `kubectl` at the unified-dev cluster (kubeconfig `~/.kube/unified-dev`).

```bash
# Kargo projects - all should be "Synced and ready"
kubectl get projects.kargo.akuity.io

# A module's Applications - want Synced / Healthy
kubectl -n argocd get applications.argoproj.io | grep digit3-

# A module's pods - want Running / 1-1
kubectl -n <module>-3-0 get pods

# A route - a protected route returns 401 (reachable, auth required); 404/502 means it is not up
curl -s -o /dev/null -w '%{http_code}\n' https://<product>-3.unified-dev.digit.org/<path>
```

A service is "done" when its Application is **Synced / Healthy**, its pods are **Running**, and its
route answers (401 on a protected path, 200 on an open one).

## How things are kept in sync

- **Argo CD** installs each chart and continuously compares the cluster to the repository.
  A GitHub webhook refreshes it the moment a change is merged, so there is no long wait.
- **App-of-apps.** A top-level Application renders the ApplicationSets, which render the service
  Applications. A change to the project list or an ApplicationSet flows down one layer at a time,
  so a structural change can take a couple of reconcile cycles to fully appear even with the
  webhook.
- **`prune: false` is deliberate.** When you remove something from git, Argo CD does **not**
  automatically delete the live object - it flags it as out-of-sync and waits. This prevents an
  accidental deletion from a bad merge. Removing a retired namespace, Application, or database is a
  deliberate manual step, done only after confirming nothing valuable is in it.

## Guardrails that are enforced for you

You do not have to remember all of these - the system refuses the unsafe action:

- An Application may only pull from the repos in its **AppProject `sourceRepos`** and deploy into
  its **`destinations`**. Anything else is refused at sync time.
- The kargo-managed render **fails** if a service points at a layout or namespace that is not in
  the module's allowed namespaces.
- `global.mode` must be exactly `prod` or `dev`; any other value fails the chart render with a
  clear message.
- Two ingresses cannot claim the same host and path; the second is rejected by the ingress
  admission check (see troubleshooting below).

## Troubleshooting

### A service is CrashLooping right after onboarding

Check the pod's logs first (`kubectl -n <ns> logs <pod>`). The usual causes:

- **Wrong image.** Confirm `global.mode: prod` so the released image is used. In `dev` mode a
  stale `image.tag` override would be used instead.
- **Missing dependency.** A service that needs the database or vault will crashloop until the
  backbone is up and the service's credentials/secrets exist.
- **A setting the chart rejects.** Read the exact error; it usually names the key.

### A new ingress will not come up / sync error "host and path already defined"

The ingress admission check refuses a second ingress for the same host + path. This happens when
an old version of a service still owns the route. Resolve by removing the old owner first (an
old, retired ingress), then the new one is admitted on the next sync. Never force two owners of
the same route.

### Everything is "OutOfSync" and nothing applies, with no error

This looks like a stuck sync: Applications sit OutOfSync with an operation in `Running` and no
error anywhere. The usual root cause is the **Argo CD application-controller being restarted**
(for example out-of-memory): a controller that restarts mid-sync resumes the operation on startup
and never finishes it, so every sync wedges. Check the controller pod:

```bash
kubectl -n argocd get pod argocd-application-controller-0
# CrashLoopBackOff + reason OOMKilled means it needs more memory
```

The controller's memory is set in the vendored chart values
(`charts/backbone-services/argo-cd/values.yaml`, `controller.resources`). Argo CD here is
installed by `helm upgrade`, not by Argo CD itself, so a live change to it is not auto-reverted;
but the durable fix is to raise the value in that file and run the helm upgrade so the install
matches git.

### A removed object is still on the cluster

That is `prune: false` working as designed. After the removal is merged, delete the orphaned
object manually - but first confirm it holds nothing valuable (check databases for real data,
check that no other module references it). Deleting namespaces, databases, or secrets is never
done on a hunch.

### A Kargo project file exists but nothing happens

The project is not registered. Add its name to
`charts/argo-cd/unified-dev/kargo/kargo-app-set-pipelines.yaml` and its namespace to
`charts/argo-cd/unified-dev/kargo/kargo-app-project.yaml`.

## Safe-change checklist (apply to every change)

- [ ] The change is only Kargo config, Argo CD project config, or values files - no chart edits.
- [ ] Namespaces are dashed; folders and values files are dotted.
- [ ] `global.mode` is `prod` (unless deliberately testing an unreleased build).
- [ ] Chart versions were taken from the published index, not guessed.
- [ ] YAML validates and there are no leftover copied names.
- [ ] The change is a pull request against `unified-dev`; a person merges it.
- [ ] After merge: Kargo project ready, Applications Synced / Healthy, pods Running, route answers.
- [ ] Any deletion was done manually, deliberately, after confirming nothing valuable is lost.
