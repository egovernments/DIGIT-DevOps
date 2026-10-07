# postgresql-18

PostgreSQL 18, managed by the [CloudNativePG](https://cloudnative-pg.io) operator.

Renders a single `Cluster` resource (plus an optional `ScheduledBackup`) from
values. Environment overrides come from `environments/<env>.yaml`, exactly like
every other chart in `backbone-services` — there are no per-environment values
files.

---

## Setup

Six pieces. They are listed in dependency order; all of it is already done for
`unified-dev` and this is the recipe for the next environment.

### 1. Operator (once per cluster)

This chart renders a `Cluster` **custom resource** — it is a declaration, not a
workload. Nothing in it is a Pod, PVC or Service. The CloudNativePG operator is
what creates the pods, provisions the PVCs, runs `initdb`, issues TLS
certificates, maintains the `-rw`/`-ro` Services and applies the superuser
password. Without it the sync fails with `no matches for kind "Cluster"`.

`charts/argo-cd/<env>/backbone/cloudnative-pg-operator-application.yaml`

- pulls the upstream `cnpg/cloudnative-pg` chart, values inline
- `sync-wave: "-1"` so its CRDs exist before any `Cluster` is applied
- namespace `cnpg-system`, `CreateNamespace=true`
- `ServerSideApply=true` — the bundled CRDs overflow the 262144-byte
  `last-applied-configuration` annotation under client-side apply
- cluster-wide: one operator serves every namespace, so it is installed once
  per cluster, not once per database

### 2. AppProject: allow the repo and the namespace

Both are required, and the failure modes look nothing alike:

```yaml
# charts/argo-cd/<env>/backbone/backbone-app-project.yaml
sourceRepos:
  - https://cloudnative-pg.github.io/charts   # else: Unknown/Unknown, never syncs
destinations:
  - namespace: 'cnpg-system'                  # else: sync rejected
```

An Application whose source repo is not listed is rejected **before any sync is
attempted** — it reports `Unknown/Unknown` rather than `OutOfSync`, with
`InvalidSpecError: repo ... is not permitted in project`. That is the tell.

The cluster-scoped kinds the operator needs — `CustomResourceDefinition`,
`ClusterRole`, `ClusterRoleBinding`, and both webhook configurations — were
already in `clusterResourceWhitelist`.

### 3. Credentials via cluster-configs

`charts/cluster-configs/templates/secrets/postgresql-18-secret.yaml` renders
**two** secrets, because the operator consumes them through different fields:

| Secret | Consumed as | Reconciled? |
|---|---|---|
| `postgresql-18-db` | `bootstrap.initdb.secret.name` | **No** — read once at bootstrap |
| `postgresql-18-superuser-db` | `superuserSecret.name` | **Yes** — on every pass |

Both are `kubernetes.io/basic-auth` with `username` and `password`. The operator
rejects `Opaque` here, which is why this cannot reuse `db-secret.yaml`.

Names and namespaces live in `charts/cluster-configs/values.yaml`; the
credentials go in the SOPS-encrypted `environments/<env>-secrets.yaml`:

```yaml
cluster-configs:
  secrets:
    postgresql-18:
      username: coredev          # MUST equal bootstrap.owner (see §4)
      password: <generated>
      superuserPassword: <generated>
```

Generate passwords without `@ : / ? # & % ' " \` or space — every one of those
breaks a Postgres URI, a JDBC string or shell quoting somewhere in this stack.

### 4. Environment overrides

```yaml
# environments/<env>.yaml
postgresql-18:
  instances: 1
  storage: { size: 50Gi, storageClass: managed-csi }
  affinity: { topologyKey: topology.kubernetes.io/zone }
  monitoring: { enabled: true }
  bootstrap:
    owner: coredev             # MUST equal the secret's username
    database: coredb
  auth:
    existingSecret: postgresql-18-db
    superuserSecret: postgresql-18-superuser-db
```

### 5. Add to the backbone ApplicationSet

```yaml
# charts/argo-cd/<env>/backbone/backbone-app-set-backbone.yaml
- name: postgresql-18
  namespace: backbone
```

which resolves to the standard backbone pattern:

```yaml
path: deploy-as-code/helm/charts/backbone-services/postgresql-18
helm:
  valueFiles:
    - values.yaml
    - ../../../environments/<env>.yaml
```

### 6. Server-Side Diff

The appset template carries:

```yaml
annotations:
  argocd.argoproj.io/compare-options: ServerSideDiff=true
```

**Without this the Application is permanently OutOfSync.** CloudNativePG's
mutating webhook defaults ~47 fields into every `Cluster` spec — `archive_mode`,
`postgresUID`/`GID`, 23 `postgresql.parameters`, `managed.roles[].inherit`, and
so on. A client-side diff reads every one as drift, so `selfHeal` re-applies on
each pass: a sync loop that also masks genuine drift.

Server-Side Diff computes the diff from a server-side dry-run apply, so those
defaults appear on both sides and cancel out. The alternative — a hand-written
44-rule `ignoreDifferences` block — was tried and rejected: it encodes the
operator's internals into our Argo config and breaks silently the next time an
upgrade defaults a new field.

`ignoreDifferences` is still right for *intentional* divergence, such as an HPA
owning `spec.replicas`. The distinction: `ignoreDifferences` for "we
deliberately do not manage this field", Server-Side Diff for "the API server
fills this in for everyone".

### Verify

```bash
kubectl -n cnpg-system get deploy cloudnative-pg           # operator Available
kubectl get crd clusters.postgresql.cnpg.io                # CRD present
kubectl -n backbone get cluster postgresql-18              # "Cluster in healthy state"
kubectl -n backbone get pvc -l cnpg.io/cluster=postgresql-18

# role password reconciliation is live when this lists the owner
kubectl -n backbone get cluster postgresql-18 \
  -o jsonpath='{.status.managedRolesStatus}{"\n"}'

# end-to-end auth with the SOPS password, over TCP (not the unix socket --
# peer auth rejects the owner there, which looks like a failure and is not)
POD=$(kubectl -n backbone get pods -l cnpg.io/cluster=postgresql-18 -o jsonpath='{.items[0].metadata.name}')
PW=$(kubectl -n backbone get secret postgresql-18-db -o jsonpath='{.data.password}' | base64 -d)
kubectl -n backbone exec $POD -c postgres -- env PGPASSWORD="$PW" \
  psql -h postgresql-18-rw -U coredev -d coredb -tAc "select current_user, current_database();"
```

## Configuring per environment

Add a `postgresql-18:` block to `environments/<env>.yaml`. It is merged over
`values.yaml`, environment wins:

```yaml
postgresql-18:
  instances: 3
  storage:
    size: 100Gi
    storageClass: managed-csi
  affinity:
    topologyKey: topology.kubernetes.io/zone
  monitoring:
    enabled: true
```

Only state what differs — anything omitted falls through to `values.yaml`.

---

## What you get

With `releaseName: postgresql-18` in namespace `backbone`:

| Object | Name |
|---|---|
| Primary (read/write) Service | `postgresql-18-rw.backbone.svc.cluster.local:5432` |
| Replica (read-only) Service | `postgresql-18-ro.backbone.svc.cluster.local:5432` |
| App credentials | secret `postgresql-18-app` (user `app`, database `app`) |
| Superuser credentials | secret `postgresql-18-superuser` (user `postgres`) |

Passwords are generated by the operator. **Nothing is committed to git.**

```bash
kubectl -n backbone get secret postgresql-18-app -o jsonpath='{.data.password}' | base64 -d
```

Applications should connect to `-rw`. The operator repoints that Service at the
new primary during a failover or switchover, so nothing needs to know which pod
is currently primary.

---

## Portability

The defaults in `values.yaml` are deliberately platform-neutral and apply
unchanged to AKS/EKS/GKE and to bare metal, including single-node and air-gapped
installs. Two defaults exist specifically for that:

- **`storage.storageClass: ""`** — omitted from the rendered `Cluster`, so the
  operator uses the cluster's default StorageClass: `managed-csi` on AKS, `gp3`
  on EKS, `local-path` on k3s, Rook-Ceph or OpenEBS on bare metal. Naming one in
  the chart is what would break portability.
- **`affinity.topologyKey: kubernetes.io/hostname`** — bare-metal and
  single-site clusters carry no `topology.kubernetes.io/zone` labels, and
  anti-affinity keyed on a label that does not exist **silently stops spreading
  replicas**: you believe you have failover and you do not. Cloud environments
  override this to zone, where zone labels genuinely exist.

### On physical servers

- **Use block storage, not NFS.** PostgreSQL needs POSIX `fsync` semantics that
  NFS does not reliably provide; an NFS-backed data directory is a known source
  of corruption after an unclean shutdown. Ceph RBD, LVM or local PVs are fine.
- **Enable `walStorage`** so the write-ahead log sits on its own volume, ideally
  a separate physical disk. It stops WAL growth — a stalled archive, a long
  transaction — from filling the data volume and halting the database.
- **Tune the planner for local SSD/NVMe**: `random_page_cost: "1.1"` (the
  default 4.0 assumes spinning disks and over-prefers sequential scans), and set
  `effective_cache_size` to roughly 75% of node RAM.

```yaml
postgresql-18:
  instances: 3
  storage: { size: 500Gi }
  walStorage: { enabled: true, size: 50Gi }
  resources:
    requests: { cpu: "4", memory: 16Gi }
    limits:   { memory: 16Gi }
  postgresql:
    parameters:
      shared_buffers: 4GB
      effective_cache_size: 12GB
      random_page_cost: "1.1"
```

### Air-gapped installs

Mirror two images and repoint them:

```
ghcr.io/cloudnative-pg/postgresql:18-standard-trixie   -> image.repository / image.tag
ghcr.io/cloudnative-pg/cloudnative-pg:<operator tag>   -> operator Application
```

Set `imagePullSecrets` if the mirror needs credentials. The operator's Helm
chart also needs mirroring, since Argo CD pulls it from
`cloudnative-pg.github.io/charts` at sync time. This chart itself has no
dependencies to fetch.

---

## Production checklist

The defaults are safe but conservative. Before calling an environment
production:

- [ ] **`instances: 3`.** The default of 1 has no failover. Needs three
      schedulable nodes; even numbers buy nothing.
- [ ] **Backups enabled** (see below). This is the single biggest gap.
- [ ] **`resources.requests.memory == limits.memory`.** A wide gap invites node
      overcommit, and a database OOMKilled mid-write costs far more than one
      scheduled conservatively. CPU is intentionally left unlimited —
      throttling during a checkpoint is worse than letting it burst.
- [ ] **`shared_buffers` ≈ 25% of the memory request**, raised together with it.
      It is allocated up front, so raising it alone gets the pod OOMKilled.
- [ ] **`monitoring.enabled: true`** where kube-prometheus-stack exists.
- [ ] **Consider `enableSuperuserAccess: false`** — app user only is the tighter
      posture.
- [ ] **Restore tested.** An untested backup is not a backup.

---

## Backups

Off by default because they need a bucket and credentials that differ per site.
The same `s3` block serves both worlds: point `endpointURL` at MinIO on-prem
(already deployed in this repo's `backbone` namespace) or at the cloud object
store. The operator also supports Azure Blob and GCS natively.

```yaml
postgresql-18:
  backup:
    enabled: true
    destinationPath: s3://postgresql-18-backups/
    endpointURL: http://minio.backbone.svc.cluster.local:9000
    credentialsSecret: postgresql-18-backup-creds   # keys: ACCESS_KEY_ID, ACCESS_SECRET_KEY
    retentionPolicy: 30d
    scheduledBackup:
      enabled: true
      schedule: "0 0 2 * * *"
```

Create the credentials Secret from the SOPS-encrypted
`environments/<env>-secrets.yaml`. **Never inline the keys** — the chart fails
the render rather than let `backup.enabled` go out without a
`credentialsSecret` or `destinationPath`, because either omission produces a
cluster that looks backed up and is not.

Two things that routinely catch people out:

- **CNPG cron has six fields and leads with seconds.** `"0 0 2 * * *"` is 02:00
  daily. The familiar five-field `"0 2 * * *"` is rejected.
- **`backup.enabled` alone only archives WAL.** Point-in-time recovery replays
  WAL *on top of a base backup*, so without `scheduledBackup.enabled` there is
  nothing to replay onto. Enable both.

---

## Upgrades

Patch releases within 18.x arrive automatically: `image.tag` pins major and
variant (`18-standard-trixie`) while the patch level floats. With
`instances: 3` and `primaryUpdateMethod: switchover`, the operator promotes a
standby first, so the update costs seconds rather than a full restart.

A **major** version change (18 → 19) is a migration, not a values bump.
CloudNativePG will not perform it in place; plan it with a dump/restore or the
operator's import facility.

---

## Troubleshooting

Every one of these was hit while bringing `unified-dev` up.

### Application is `Unknown` / `Unknown`, never syncs

```
InvalidSpecError: application repo https://cloudnative-pg.github.io/charts
                  is not permitted in project 'backbone-project'
```

The AppProject's `sourceRepos` does not list the chart repo. Note it is
`Unknown`, not `OutOfSync` — a rejected spec never reaches a sync attempt, so it
does not look like a sync problem. See §2.

### `no matches for kind "Cluster" in version "postgresql.cnpg.io/v1"`

The operator's CRDs are not installed yet. Expected on a first sync and
self-correcting: the Application retries, and the `sync-wave: "-1"` on the
operator means it only happens if the operator itself is blocked. Check §1 and
§2 before assuming it will resolve.

### Owner cannot authenticate, superuser can

```
FATAL:  password authentication failed for user "coredev"
```

The `username` in `postgresql-18-db` does not match `bootstrap.owner`. The
operator creates the role from `owner` and the credentials never attach to it —
so the database ends up owned by a role those credentials cannot authenticate
as. The superuser is unaffected because `superuserSecret` is reconciled
separately.

**This cannot be fixed by editing values.** `initdb` runs once, when PGDATA is
empty, and the whole `bootstrap` stanza is skipped forever after. Argo will
happily report `Synced` with the corrected spec while the running database keeps
the old role and database names — the object matches git, the database does not.

Fix: align `username` and `bootstrap.owner`, then **delete the Cluster** so
`initdb` re-runs. This destroys the database and its PVC; Argo recreates both
within a minute.

```bash
# confirm it is empty first -- this is destructive
kubectl -n backbone exec postgresql-18-1 -c postgres -- \
  psql -d <db> -tAc "select count(*) from pg_stat_user_tables;"
kubectl -n backbone delete cluster postgresql-18
```

Push the corrected config **before** deleting. Otherwise Argo recreates from the
current revision and bootstraps the same wrong values again.

### Password rotation does not reach the database

Expected without `managedRoles`. `bootstrap.initdb.secret` is an input to one
`initdb` run, not a declaration of desired state — changing it updates the
Secret and nothing else.

`managedRoles.ownerFromSecret: true` (the default) renders
`spec.managed.roles`, which **is** reconciled on every pass, so a password
change in SOPS is applied to the running database. Confirm with:

```bash
kubectl -n backbone get cluster postgresql-18 -o jsonpath='{.status.managedRolesStatus}'
# byStatus.reconciled should list the owner
```

Rotation is a coordinated change: anything holding a cached connection string
starts failing auth on reconnect.

### Permanently `OutOfSync` on the `Cluster`

Server-Side Diff is not enabled — see §6. To confirm the spec is genuinely
correct and the diff is the problem, reproduce what Argo does:

```bash
helm template postgresql-18 . -f ../../../environments/<env>.yaml > /tmp/pg.yaml
kubectl apply --server-side --dry-run=server --field-manager=argocd-controller \
  --force-conflicts -f /tmp/pg.yaml -o json
# compare .spec against the live object -- zero differences means the spec is fine
```

### Still `OutOfSync` right after enabling Server-Side Diff

A stale comparison; the app was last evaluated under the old mode. Force a
re-evaluation:

```bash
kubectl -n argocd annotate app backbone-postgresql-18 \
  argocd.argoproj.io/refresh=hard --overwrite
```

### `psql` fails inside the pod with "Peer authentication failed"

Not a real failure. Connecting over the unix socket uses peer auth, which maps
the OS user, so only `postgres` succeeds. Use TCP against `postgresql-18-rw`
with `PGPASSWORD`, as in the verify block above.

### Deprecation warning on apply

```
Warning: spec.monitoring.enablePodMonitor is deprecated and will be removed in
a future release.
```

Emitted when `monitoring.enabled: true`. It works today and the PodMonitor is
created. When a future CloudNativePG release drops the field, this chart will
need to render a `PodMonitor` itself.

---

## Image provenance

`ghcr.io/cloudnative-pg/postgresql` is built on **official Debian slim images
using the PostgreSQL Global Development Group (PGDG) apt packages** — the same
upstream binaries as `docker.io/library/postgres`. The PostgreSQL project itself
ships packages, not containers, so neither image is "official" in the sense of
being built by PGDG; the difference is who assembles the container. These are
the ones the operator is tested against.

`bitnami/postgresql` was evaluated and rejected: since Bitnami's 2025 registry
change the free `docker.io/bitnami/postgresql` repository holds only `latest`
(plus digest and signature tags), with every pinned tag moved behind their paid
registry — and the chart's default image is literally `bitnami/postgresql:latest`.
An unpinned tag on a database is how an unannounced major-version jump refuses
to start against an existing `PGDATA`.
