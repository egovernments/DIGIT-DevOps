# Deployment Docs

How services are deployed and updated on the Helm + ArgoCD environments in this repo (`uat-saas`, `digit-lts`, `digit-health-lts`, `test-lts`).

- [Deploying a New Service](./deploying-a-new-service.md)
- [Editing an Existing Service's Deployment](./editing-an-existing-service.md)

## How it fits together (quick mental model)

```
deploy-as-code/helm/charts/<category>/<service>/   → the Helm chart for one service (values.yaml + thin templates that call the common chart)
deploy-as-code/helm/charts/common/                 → shared library chart (_deployment.yaml, _service.yaml, _ingress.yaml) used by every service chart
deploy-as-code/helm/environments/<env>.yaml        → per-environment overrides (image tags, feature flags), passed as a second Helm values file
deploy-as-code/helm/environments/<env>-secrets.yaml→ SOPS-encrypted secrets for the environment
deploy-as-code/helm/charts/argo-cd/egov/<env>-egov-appset-<category>.yaml → ArgoCD ApplicationSet that turns each list entry into a synced Application
```

`<category>` is one of: `core-services`, `business-services`, `frontend`, `health-services`, `accelerators`, `backbone-services`, `common-services`, and a few others (`digit-works`, `ifix`, `sanitation`, `urban`, `utilities`).

**Important, non-obvious fact about this repo:** the ArgoCD ApplicationSets under `charts/argo-cd/egov/*.yaml` use a static inline `list` generator (the service list is hardcoded in the YAML), and nothing in the cluster watches that path in git to auto-apply changes. **Pushing to git alone does not add/remove services from ArgoCD.** After pushing a change to an ApplicationSet file, you must also `kubectl apply -f` that file against the target cluster for the new/removed service to show up as an Application. This was confirmed while deploying `notify` to `uat-saas` on 2026-09-17 — the `notify` Application only appeared after the ApplicationSet manifest was applied directly.
