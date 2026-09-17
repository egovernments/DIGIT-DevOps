# Editing an Existing Service's Deployment

This covers changes to a service that's already deployed and already has an ArgoCD Application (e.g. bumping an image tag, changing an env var, adjusting resources, toggling a feature flag). For adding a brand-new service, see [deploying-a-new-service.md](./deploying-a-new-service.md).

## Where to make the change

| Change | File |
|---|---|
| Image tag (new release) | `deploy-as-code/helm/environments/<env>.yaml` → `<service>.image.tag` (and `<service>.initContainers.dbMigration.image.tag` if it has DB migrations) |
| Env var value / feature flag | `deploy-as-code/helm/environments/<env>.yaml` (if it's meant to vary per environment) or `deploy-as-code/helm/charts/<category>/<service>/values.yaml` (if it's a chart-wide default) |
| New env var | Add it to the `env: \|` block in `deploy-as-code/helm/charts/<category>/<service>/values.yaml`, then optionally override its value per environment |
| Resource requests/limits | `resources: \|` block in the service's `values.yaml` |
| Replica count | `replicas` in `values.yaml` or an environment override |
| Ingress path / context | `ingress.context` in `values.yaml` |
| Secret value | `deploy-as-code/helm/environments/<env>-secrets.yaml` (SOPS-encrypted — edit with `sops <file>`, don't hand-edit the ciphertext) |

Check the service's current `values.yaml` and the relevant `<env>.yaml` block first — most edits are a one- or two-line change to an existing key, not new structure.

## Applying the change

Unlike adding a new service, **editing an already-deployed service does not require touching the ApplicationSet or re-applying anything with `kubectl`.** The service already has a live ArgoCD `Application` (not just an entry in the ApplicationSet's static list), and that `Application` has:

```yaml
syncPolicy:
  automated:
    prune: false
    selfHeal: true
```

That means the normal ArgoCD Application controller (not the ApplicationSet controller) watches the git repo and applies changes automatically once it detects the new commit — no manual `kubectl apply` needed. So the flow is just:

```bash
git add deploy-as-code/helm/environments/<env>.yaml   # or the chart's values.yaml
git commit -m "fix(<env>): bump <service> image tag to <tag>"
git push origin <env-branch>
```

By default ArgoCD polls git every ~3 minutes. If you need it immediately:

```bash
argocd app sync <service>
# or, without the argocd CLI configured:
kubectl patch application <service> -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
```

## Verifying

```bash
kubectl get application <service> -n argocd
kubectl get pods -n egov | grep <service>
kubectl rollout status deployment/<service> -n egov
```

- `SYNC STATUS: Synced`, `HEALTH STATUS: Healthy`
- New pod picked up the intended change: `kubectl get pod <pod> -n egov -o jsonpath='{.spec.containers[0].image}'` to confirm the image tag, or `kubectl exec` / `kubectl logs` to confirm an env var took effect
- If the rollout doesn't happen: check `kubectl describe application <service> -n argocd` for sync errors (e.g. a values.yaml typo breaking the Helm template render — validate first with `helm template . -f values.yaml -f ../../../environments/<env>.yaml` from the chart directory)

## Note on `values.yaml` vs. `<env>.yaml`

The chart's own `values.yaml` is the default for *all* environments that deploy this chart. `environments/<env>.yaml` is layered on top per-environment (see `helm.valueFiles` in the Application/ApplicationSet spec — it's always `values.yaml` then `../../../environments/<env>.yaml`, so the environment file wins). Prefer putting environment-specific values (image tags, per-env feature flags, per-env credentials wiring) in the environment file, and keep `values.yaml` as the shared default so other environments aren't affected by a change meant for one.
