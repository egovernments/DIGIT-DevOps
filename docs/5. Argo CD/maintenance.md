# Argo CD - Maintenance

<sub>[Argo CD](README.md) - Maintenance</sub>

## Sync policy

Generated Applications use:

```yaml
syncPolicy:
  automated:
    prune: false        # removals are deliberate
    selfHeal: true      # drift is reverted
  syncOptions:
    - ApplyOutOfSyncOnly=true
    - ServerSideApply=true
  retry:
    limit: 10
    backoff: { duration: 5s, factor: 2, maxDuration: 3m0s }
ignoreDifferences:
  - group: apps
    kind: Deployment
    jsonPointers: [/spec/replicas]
```

| Situation | Behaviour |
|---|---|
| Someone edits a managed object on the cluster | Reverted within seconds; change git instead |
| A resource disappears from the render | Stays on the cluster until removed by hand (`prune: false`) |
| Two ApplicationSets generate the same Application name | The second fails "already owned by another ApplicationSet" |
| An ApplicationSet is deleted | Its Applications are deleted too, unless deleted with `--cascade=orphan` |

## Where each value belongs

| Value | Location |
|---|---|
| Shared by every service in a module (db host, broker, domain, time zone) | `cluster-configs.configmaps.<shared-config>.data` in the module env file |
| Addresses of the services a module calls | `cluster-configs.configmaps.<service-host-config>.data` |
| A password, key, token, certificate | The module's `-secrets.yaml`, SOPS-encrypted |
| One service's setting (replicas, ingress, an override) | That service's section in the env file |
| Chart version and image tag | Written by Kargo, or by pull request in the Argo CD only model |
| A value used by every module on the cluster | The cluster-wide configuration, owned by the platform team |

## Secrets and SOPS

Secrets live in git **encrypted** with SOPS, as a `<module>-<env>-secrets.yaml` twin of the env file. Argo CD's repo-server decrypts them at render time with a key it is allowed to use. Rules live in `deploy-as-code/helm/.sops.yaml`.

Two key backends are in use across environments:

- **AWS KMS** - the repo-server assumes an AWS role (IRSA) that can decrypt with the KMS key.
- **Azure Key Vault** - the repo-server uses an Azure **workload identity**: a managed identity federated to the `argocd-repo-server` ServiceAccount, granted Crypto User on the vault key. The AKS webhook injects the token when the ServiceAccount has the `azure.workload.identity/client-id` and `tenant-id` annotations and the pod has the `azure.workload.identity/use: "true"` label.

Working with SOPS files:

- `sops updatekeys` and `sops -e` need `.sops.yaml` found from the current directory - run them from the directory that holds it.
- `sops -d` (decrypt) does not need `.sops.yaml`.
- `sops -e > file` truncates the file if encryption fails. Write to a temp file and move it into place, and shred plaintext temps.
- Rotate or re-key by re-encrypting and raising a pull request. Never commit plaintext.

To re-key a whole environment to a new backend: create the vault and key, grant the repo-server identity access, point `.sops.yaml` at the new key, `sops updatekeys` every secrets file, and roll out the repo-server with the identity wired in.

## Argo CD managing itself

Argo CD can deploy its own chart as one of its Applications, so upgrades and config changes go through git like everything else.

- The self-management Application's `releaseName` **MUST** equal the install's immutable `app.kubernetes.io/instance` label. If they differ, the rendered Service selectors stop matching the running pods and the control plane loses its own endpoints - a cluster-wide outage. Match the release name the cluster was first installed with.
- Changing reconciliation timing (for example `timeout.reconciliation` and jitter) is a values change applied through this Application. Until the first self-managed sync runs, the cluster keeps whatever the manual install set.

## Controller resources

The application-controller's memory scales with the number of Applications it manages.

- If it is OOMKilled it CrashLoops, and anything waiting on it (a new install, a stuck sync) stalls.
- Raise the limit through the chart values and a pull request (for example 512Mi to 1Gi).
- A StatefulSet RollingUpdate will **not** recreate an already-CrashLooping pod. After merging the limit bump, delete the pod so it is recreated with the new limit.
- Any increase to a resource limit or node capacity is a cost change - confirm it before applying.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Application OutOfSync, never Synced | Sync failing | Read the Application's Conditions and events; fix the cause in git; Hard Refresh |
| `ComparisonError: chart ... not found` | The pinned chart version was unpublished | Re-publish that version, or pin one that exists |
| `CreateContainerConfigError` after a chart change | The chart references a ConfigMap/Secret key not in the env file | Add the missing key to the env file; renders do not catch this, only runtime |
| ApplicationSet: "project does not exist" | The AppProject was not reconciled yet | Ensure the AppProject file is present; refresh the ApplicationSet |
| "already owned by another ApplicationSet" | Two ApplicationSets generate the same name | Hand ownership over (below) |
| Namespace stuck / resource lingers after a file was deleted | `prune: false` | Delete the object by hand |

## Retire an application

1. Remove the service (from the Kargo config, the ApplicationSet list, or the env file) and raise a pull request.
2. After merge, because `prune: false`, the workload stays on the cluster. Delete the Application and its namespaced objects by hand.
3. Remove the namespace only if no other Application owns it.

## Move Applications between ApplicationSets

1. Delete the source ApplicationSet with `--cascade=orphan` so its Applications survive.
2. Apply the new ApplicationSet that generates the same Application names.
3. Confirm each Application is now owned by the new ApplicationSet and stays Synced.
