# DIGIT 3.0 core — Kargo-promoted

Kargo project `digit-core3-0` (dev cluster) promotes these services DEV → QA → UAT.
Each promotion carries one Freight per service:

| Artifact | Source | Becomes |
|---|---|---|
| App image tag | `docker.io/egovio/<service>` (`master-*`, `flyway-branch-*`) | `<chart>.image.tag` **and** `<chart>.initContainers.dbMigration.image.tag` |
| Chart version | `https://helm.digit.org/digit3/core`, chart `<chart>` | the umbrella's dependency version |
| Config commit | this directory, on `unified-dev` | `values.yaml` + `stages/<env>.yaml` |

## Who writes what

| Path | Written by | Read by |
|---|---|---|
| `digit3-core/<service>/Chart.yaml` | people (PR) | Kargo |
| `digit3-core/<service>/values.yaml` — same in every env | people (PR) | Kargo |
| `digit3-core/<service>/stages/<env>.yaml` — differs per env | people (PR) | Kargo |
| `releases/digit3-core/<service>/` on `unified-<env>` | **Kargo only** | that env's Argo CD |

A merged change here deploys nowhere until its Freight is promoted. Values nest
under the chart name (umbrella chart). Maps merge key by key; strings (`env`,
`resources`) and lists replace whole. Never set image tags or the dependency
version here — Kargo writes both.

`environments/unified-dev.yaml` is deliberately not layered in: its top-level
DIGIT 2.x keys (`billing:`, `boundary:`, …) would be applied to the 3.0 charts.

## Current state

- `helm.digit.org/digit3/core` is not published yet, so the Warehouses discover
  no chart and no Freight can be assembled until it is.
- App images are not yet built with `flyway-branch-*` tags (only `-db` images are).
- Only unified-dev deploys (namespace `digit3`, ingress off). Promotions to qa/uat
  write `releases/digit3-core/` on those branches; no Application reads it yet.
- Verification is off until DB/secrets for 3.0 are wired in `digit3`.
- `notify` and `boundary-management` are not included: no 3.0 chart exists yet.

## Adding a service

1. `digit3-core/<service>/` — copy an existing one; set the dependency `name` to the chart.
2. `charts/kargo/config/projects/digit-core3-0.yaml` — add the service entry.
3. `charts/argo-cd/unified-dev/digit3-core/digit3-core-app-set.yaml` — add the element.
