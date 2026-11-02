# 07 Access Control

Access is granted per layer, always with the least privilege that does the job.

| Layer | Controls | Defined in |
|---|---|---|
| Kargo | Who can view a project, assemble Freight, and promote to which stages | The project config `teams:` list |
| Argo CD | Which repositories and namespaces a module's Applications may use | The module's AppProject |
| Git | Who can change an environment | Branch protection and pull-request review |
| Cluster | Who can inspect and debug workloads | RBAC: ServiceAccount + Role/ClusterRole |
| Database | Who can read data | Database roles |

## Kargo

Users sign in through SSO; their team memberships arrive as a groups claim (`<github-org>:<team-slug>`). Kargo maps a claim to a ServiceAccount through the `rbac.kargo.akuity.io/claim.groups` (or `claim.email`) annotation, and that ServiceAccount's Role decides what the user can do.

Declare access once, in the project config:

```yaml
teams:
  - name: platform
    role: admin                       # full control of the project
    groups: ["<github-org>:<platform-team>"]
  - name: developers
    role: viewer                      # read only
    groups: ["<github-org>:<developer-team>"]
  - name: dev-promoters
    role: promoter
    promoteStages: [dev]              # may promote to dev only
    manageFreight: true               # may assemble Freight
    groups: ["<github-org>:<release-team>"]
  - name: uat-promoters
    role: promoter
    promoteStages: [qa, uat]
    emails: ["<person>@<domain>"]     # named individuals
```

| Role | Can |
|---|---|
| `viewer` | See stages, warehouses, Freight and verification results |
| `promoter` | Viewer, plus promote. With `promoteStages`, only to those stages. |
| `admin` | Everything in the project |
| `manageFreight` (flag) | Create, update and delete Freight. Freight is project-wide, so grant it only to the team that assembles releases. |

Raw-manifest equivalent: [templates/kargo/manifests/team-rbac.yaml](templates/kargo/manifests/team-rbac.yaml). The cluster-level ServiceAccount that grants login and the project list must live in a namespace the Kargo API server scans (`GLOBAL_SERVICE_ACCOUNT_NAMESPACES`).

## Argo CD

- **AppProjects** limit what a module's Applications can touch (repositories, namespaces, cluster-scoped kinds); see [05](05-argocd-guide.md#bootstrap-and-appprojects).
- **User access** to the Argo CD UI and API follows your Argo CD RBAC policy; grant `sync`/`override` only to platform operators.

## Cluster read access for service teams

For teams that need to debug their workloads without changing them, use [templates/access/cluster-readonly-access.yaml](templates/access/cluster-readonly-access.yaml).

| Allowed | Not allowed |
|---|---|
| View pods, logs, deployments, statefulsets, replicasets, services, endpoints, ingresses, configmaps, events, namespaces | Read Secrets |
| `exec`, `port-forward` and `attach` into pods | Create pods; change or delete Deployments |
| Delete pods (to restart them) | Anything cluster-scoped |

1. Apply the manifest (ServiceAccount, ClusterRole, binding, token Secret).
2. Build a kubeconfig from the token and the cluster CA. **Treat the kubeconfig as a secret.**
3. Verify with `kubectl auth can-i --as=system:serviceaccount:kube-system:<team>-readonly …`: the allowed actions return `yes`, and `get secrets` returns `no`.
4. Record who holds it and how to revoke it: delete the token Secret.

Where a team works in a fixed set of namespaces, bind the same rules with RoleBindings in those namespaces instead of a ClusterRoleBinding.

## Database read access

Never hand out an administrator login as "read access". Create a dedicated role ([templates/access/database-readonly-role.sql](templates/access/database-readonly-role.sql)):

```sql
CREATE ROLE <readonly_user> LOGIN PASSWORD :'pw';
GRANT CONNECT ON DATABASE <database> TO <readonly_user>;
GRANT pg_read_all_data TO <readonly_user>;
```

- **Verify** that it can `SELECT`, and that `CREATE TABLE` and `UPDATE` are refused.
- **Store the password** in your secrets store; never in git or in messages.
- **Database UIs** (for example pgAdmin): point the *read* server entry at `<readonly_user>`. If the UI's server list is generated from git, change it there, otherwise self-heal reverts the edit. Give the team a UI login that can see **only** the read server.
