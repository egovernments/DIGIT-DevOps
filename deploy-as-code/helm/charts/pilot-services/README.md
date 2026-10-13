# Kargo config-promotion pilot

Two podinfo services that prove config and image can be promoted together, with
values that differ per environment, and that nothing deploys except by promotion.

| Service | Demonstrates |
|---|---|
| `pilot-config` | env vars (`extraEnv.app`) and a mounted config file (`configFiles`) |
| `pilot-resources` | replicas and CPU/memory (`resources`) |

Kargo project `unified-pilot` (dev cluster), workload namespace `pilot` on dev, qa and uat.

## Who writes what

| Path | Branch | Written by | Read by |
|---|---|---|---|
| `charts/pilot-services/<svc>/values.yaml` | `unified-dev` | people (PR) | Kargo Warehouse |
| `charts/pilot-services/<svc>/stages/<env>.yaml` | `unified-dev` | people (PR) | Kargo Warehouse |
| `charts/releases/<svc>/` | `unified-<env>` | **Kargo only** | that env's Argo CD |

`values.yaml` holds what every environment shares; `stages/<env>.yaml` holds only
what differs. On promotion Kargo copies the chart from the Freight's commit to
`charts/releases/<svc>/` and writes its `values.yaml` as
`values.yaml + stages/<env>.yaml + image.tag`. Maps merge key by key; strings
(`env`, `resources`, `args`) and lists replace whole.

## Demo runbook

1. Promote the first Freight to `*-dev`, then `*-qa`, then `*-uat`. Each env shows its
   own colour/message; `pilot-resources` runs 1 / 2 / 2 replicas.
2. In a PR, add an env var to `pilot-config/values.yaml` and give it a different value
   in `stages/qa.yaml`. Merge. **No cluster changes**; Kargo shows new Freight.
3. Promote it to dev: dev changes, qa/uat do not.
4. Promote it to qa: qa gets the var with the qa value, from the same commit.
5. Promote an older Freight: config and image roll back together.

Check an env: `kubectl -n pilot port-forward deploy/pilot-config 9898` and open
http://localhost:9898.

## Removing the pilot

Delete `charts/pilot-services/`, `charts/releases/pilot-*` on each env branch,
`charts/argo-cd/unified-<env>/pilot/`, `config/projects/unified-pilot.yaml`, the
`unified-pilot` appset element, and `pilot`/`unified-pilot` from the namespace lists.
Every appset here has `prune: false`, so then delete the Applications and namespaces
by hand.
