# DIGIT 3.0 core — Kargo-promoted

Kargo project `digit-core3-0` (dev cluster). Every service has two kinds of Freight,
and a Stage always holds one of each:

| Freight | Warehouse | Contains | Promoted to |
|---|---|---|---|
| **Release** | `<service>` | app image tag (`docker.io/egovio/<service>`, `master-*` / `flyway-branch-*`), chart version (`helm.digit.org/digit3/core`), commit of `Chart.yaml` + `values.yaml` | dev → qa → uat, **or** straight to any stage |
| **Env config** | `<service>-<env>-config` | commit of `stages/<env>.yaml` only | that one env, directly |

Promoting either one re-renders `releases/digit3-core/<service>` on the env's
branch from both: a new build keeps the env's config, and a config change keeps
the env's build. The app tag is written to the app **and** the `-db` migration image.

**Nothing is automatic.** Freight is assembled by hand (all Warehouses are
`Manual`) and every promotion is clicked by a person. uat only accepts `master-*`
builds, however the Freight arrives.

| You change | Promote | Affects |
|---|---|---|
| `stages/qa.yaml` (replicas, resources, env values) | `<service>-qa-config` Freight → `<service>-qa` | qa only |
| New build or chart version | release Freight → any stage, in any order | the stages you promote to |
| `values.yaml` (shared) | release Freight → each stage you want | the stages you promote to |
| Roll back | an older Freight of the same kind | that stage only |

## Who writes what

| Path | Written by | Read by |
|---|---|---|
| `digit3-core/<service>/Chart.yaml` | people (PR) | Kargo, release Warehouse |
| `digit3-core/<service>/values.yaml` — same in every env | people (PR) | Kargo, release Warehouse |
| `digit3-core/<service>/stages/<env>.yaml` — differs per env | people (PR) | Kargo, `<service>-<env>-config` Warehouse |
| `releases/digit3-core/<service>/` on `unified-<env>` | **Kargo only** | that env's Argo CD |

A merged change here deploys nowhere until its Freight is promoted.
`env` and `resources` are strings in these charts: a stage file that changes them
must restate the whole block (the bundled `common` has no `extraEnv.app` hook). Values nest
under the chart name (umbrella chart). Maps merge key by key; strings (`env`,
`resources`) and lists replace whole. Never set image tags or the dependency
version here — Kargo writes both.

`environments/unified-dev.yaml` is deliberately not layered in: its top-level
DIGIT 2.x keys (`billing:`, `boundary:`, …) would be applied to the 3.0 charts.

## Current state

- `helm.digit.org/digit3/core` is not published yet, so release Warehouses discover
  no chart and no release Freight can be assembled until it is. A Stage needs a
  release Freight before its env-config Freight can be promoted.
- App images are not yet built with `flyway-branch-*` tags (only `-db` images are).
- Only unified-dev deploys (namespace `digit3`, ingress off). Promotions to qa/uat
  write `releases/digit3-core/` on those branches; no Application reads it yet.
- Verification is off until DB/secrets for 3.0 are wired in `digit3`.
- `notify` and `boundary-management` are not included: no 3.0 chart exists yet.

## Adding a service

1. `digit3-core/<service>/` — copy an existing one; set the dependency `name` to the chart.
2. `charts/kargo/config/projects/digit-core3-0.yaml` — add the service entry.
3. `charts/argo-cd/unified-dev/digit3-core/digit3-core-app-set.yaml` — add the element.
