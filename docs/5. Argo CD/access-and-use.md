# Argo CD - Access and Use

<sub>[Argo CD](README.md) - Access and Use</sub>

## Reach the UI

Argo CD's UI is served behind the environment's gateway, for example `https://test-lts.digit.org/argocd`. Access to it is usually fronted by an SSO proxy (oauth2-proxy), so you authenticate once at the gateway. The platform team grants UI access.

For scripted or break-glass work, port-forward the server Service and use the `argocd` CLI or `kubectl` against the `argocd` namespace.

## Read an Application's state

Each service is one Application. The two fields you read most:

| Field | Meaning |
|---|---|
| **Sync** | Synced = the cluster matches git; OutOfSync = git has changed and a sync is due or failing |
| **Health** | Healthy = pods Ready; Progressing = rolling out; Degraded = failing |

Open an Application to see the rendered resources, the live manifest vs the desired manifest (the diff), and the pod and event logs.

## Check a deployment after a change

After a promotion or a merged pull request:

1. The owning ApplicationSet re-reads the env file (about 60s).
2. The Application goes OutOfSync, then Progressing as new pods roll out.
3. It returns to Synced and Healthy.

If it does not, read the Application's diff and events, and the pod logs, then see [maintenance.md](maintenance.md#troubleshooting).

```sh
# quick check from the CLI
kubectl -n argocd get applications
kubectl -n <namespace> get pods
kubectl -n <namespace> logs deploy/<service>
```

## Refresh an Application or ApplicationSet

Argo CD polls on its own, but you can force a re-read:

- **Hard Refresh** on an Application re-renders from git immediately (useful after publishing a chart version it was waiting on).
- For an ApplicationSet that reported a missing AppProject, refresh it once the AppProject exists so it generates its Applications.

## Access control

Access is granted per layer, least privilege:

| Layer | Controls | Defined in |
|---|---|---|
| Argo CD UI | Who can view and act on Applications | The server's SSO / RBAC |
| AppProject | Which repositories and namespaces a module's Applications may use | The module's AppProject |
| Cluster | Who can inspect and debug workloads | Kubernetes RBAC (ServiceAccount + Role/ClusterRole) |
| Database | Who can read data | Database roles |

For read-only cluster and database access for support engineers, start from the templates:

- [`../templates/access/cluster-readonly-access.yaml`](../Templates/access/cluster-readonly-access.yaml)
- [`../templates/access/database-readonly-role.sql`](../Templates/access/database-readonly-role.sql)

## Undo a release

- With Kargo: promote the previous Freight (see [Kargo access-and-use](<../4. Kargo Promotions/access-and-use.md#roll-back>)).
- Without Kargo: revert the commit that changed the version keys on the environment branch.

Do not edit the workload on the cluster directly - `selfHeal` reverts it within seconds. Change git.
