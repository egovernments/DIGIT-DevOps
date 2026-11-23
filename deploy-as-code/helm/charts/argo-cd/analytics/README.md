# Analytics on digit-lts (Superset + ClickHouse)

Deployed by **Kargo project `analytics`** (https://kargo-latest.digit.org), from the
packaged charts at `https://helm.digit.org/digit3/analytics`
(`egovernments/helm-charts` `charts/digit3/analytics/`).

| Service | Chart | Namespace | Freight |
|---|---|---|---|
| `clickhouse-operator` | `clickhouse-operator` (ClickHouse Inc. operator v0.0.8) | `clickhouse-operator` | chart version |
| `clickhouse` | `clickhouse` (1 server + 1 Keeper, 25.7.8.71) | `clickhouse` | chart version |
| `superset` | `superset` | `superset` | chart version + `egovio/superset` tag (`care-YYYYMMDD`) |

https://superset.test-lts.digit.org — username/password login (`admin`, password
`ADMIN_PASSWORD` in `superset-secret`).

## How it fits together

| File | Role |
|---|---|
| `charts/kargo/config/projects/analytics.yaml` | Kargo project: one Warehouse + one Stage (`<service>-digit-lts`) per service, the functional checks |
| `environments/test-lts.yaml` | All values (sections `clickhouse-operator`, `clickhouse`, `superset`). Kargo merges `<service>.chart-version` (and `superset.image.tag`) into it on promotion |
| `analytics-app-set.yaml` | One Application `analytics-<service>` per section **with a chart-version**; values = that section + `global` as root values |
| `analytics-app-project.yaml` | `analytics-project`: the registry, the three namespaces, the operator's cluster-scoped kinds |
| `environments/test-lts.yaml` + `test-lts-secrets.yaml` (cluster-configs) | Through `digit-lts-cluster-configs`: the three namespaces (`cluster-configs.namespaces`) and Secrets `superset-secret`, `clickhouse-users` (`cluster-configs.secrets.generic`, SOPS/Azure Key Vault) |

All of it syncs from git through `digit-lts-bootstrap`; nothing is applied by hand.
A service has no Application until its first promotion.

## First deployment

1. **Metadata database (once).** Role and database `superset` on the shared PostgreSQL 18
   (`postgresql.backbone`, CloudNativePG), with the password from
   `SQLALCHEMY_DATABASE_URI` in `superset-secret`:

   ```sql
   CREATE ROLE superset LOGIN PASSWORD '<password>';
   CREATE DATABASE superset OWNER superset;
   ```

2. **Promote in order**, each after the previous one verified: `clickhouse-operator`
   (installs the CRDs and webhooks), `clickhouse`, then `superset` (its check needs
   ClickHouse). Assemble a Freight in each Warehouse (freight creation is manual) and
   promote it to `digit-lts`.

## Verification ("ready to use")

Every promotion, and every **Reverify** in the Kargo UI, runs read-only checks against
the cluster (`charts/kargo/checks/`). A stage is Verified only when all of them pass.
The logs of the `functional-check-<service>` Job list each PASS/FAIL.

**clickhouse-operator** (`clickhouse-operator.sh`)
- manager Deployment rolled out and stable (no restarts for 60s)
- admission webhook Service has ready endpoints
- no errors in the manager log (reported, not fatal)

**clickhouse** (`clickhouse.sh`)
- Keeper and server StatefulSets rolled out
- `app` and `otelcollector` log in with their passwords from the Secret; `default`
  refuses an empty password; a wrong password is refused
- `app` (what Superset uses) can SELECT and is refused CREATE TABLE
- Keeper reachable from the server
- HTTP `:8123/ping` through the client Service
- every `system.*_log` table has a TTL (unified-dev filled its disk with an unbounded
  `text_log`)
- data disk at least 15% free

**superset** (`superset.sh`, plus the deploy-state check on `superset-web`)
- web, worker and beat run the promoted tag and have rolled out
- `/health` OK
- metadata DB reachable and migrated to the image's head revision; `superset init` ran
  (Admin/Alpha/Gamma/sql_lab roles); admin account exists
- Redis answers; a Celery worker answers on the broker
- `psycopg2`, `clickhouse_connect` and the `clickhousedb://` dialect are present
- ClickHouse reachable from Superset (`/ping`)
- https://superset.test-lts.digit.org/health OK over valid TLS, `/login/` 200, and the API
  refuses an unauthenticated request (401)

The checks never read a Secret and never print a password: logins run inside the
containers with the credentials already in their environment. Nothing that loads the
Superset app runs inside a pod (the worker has a 1Gi limit and would be OOM-killed).

## Connecting Superset to ClickHouse

Settings → Database Connections → + Database → ClickHouse Connect:

```
clickhousedb://app:<app-password>@clickhouse-clickhouse-headless.clickhouse.svc.cluster.local:8123/default
```

`app-password` is in Secret `clickhouse-users` (namespace `clickhouse`).

## Not set up

- **GitHub team SSO.** Needs a GitHub OAuth app with callback
  `https://superset.test-lts.digit.org/oauth-authorized/github`; put
  `OAUTH_CLIENT_ID` / `OAUTH_CLIENT_SECRET` in `superset-secret` and set
  `superset.auth.oauth` (enabled, githubOrg, teamRoles) in `test-lts.yaml`.
