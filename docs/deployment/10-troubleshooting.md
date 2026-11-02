# Troubleshooting

<sub>**Deployment Guide** · Part 10 of 11 · [Contents](README.md) · Next: [Glossary](11-glossary.md)</sub>

Find the symptom, confirm the cause, apply the fix through git unless stated otherwise. Commands for checking state are in [08 Operations Runbook](08-operations-runbook.md#check-a-deployment-after-a-change).

## Kargo

| Symptom | Cause | Fix |
|---|---|---|
| Warehouse Not Ready: "No references discovered" | No tag matches the filter, or the chart is not published | Check the registry and the regex; add `extraAllowTags` for the service |
| Freight list shows an unexpected "newest" tag | Images report identical build dates | Choose the tag explicitly |
| Promotion to uat fails: "REJECTED: only master-* images may be promoted" | Non-mainline image | Promote a `master-*` build |
| Promotion fails: "key path not found" | `envFileWrite: update` and the key is not seeded | Seed the key by pull request, or switch the project to `merge` |
| Promotion succeeded, nothing deployed | No Application for the service | Add the service to the Kargo-managed config or the ApplicationSet; check the commit reached the branch |
| Project missing in the UI for a team | The team's cluster-level ServiceAccount is in a namespace the API server does not scan | Place it in a `GLOBAL_SERVICE_ACCOUNT_NAMESPACES` namespace |

## Argo CD: generation and sync

| Symptom | Cause | Fix |
|---|---|---|
| ApplicationSet: "application references project … which does not exist" | Reconciled before its AppProject existed | Refresh the ApplicationSet |
| ApplicationSet: "already owned by another ApplicationSet" | Two ApplicationSets generate the same name | Hand over ownership ([08](08-operations-runbook.md#move-applications-to-another-applicationset)) |
| ApplicationSet generates nothing; `missingkey` error | A listed service has no `chart-version` in the env file | Add the version, remove the element, or use the selector |
| Sync fails: `duplicate entries for key [name="…"]` | The chart renders an env var twice; server-side apply rejects the Deployment | Remove the duplicate in the chart, or merge env by name in the library chart |
| Sync fails: "one or more synchronization tasks are not valid", CRDs listed | The chart ships CRDs; the project allows no cluster-scoped kinds | `helm.skipCrds: true` |
| Sync fails: "namespace … is not permitted in project" | An object renders outside the AppProject's destinations | Fix the chart's namespace, or add the namespace to the project deliberately |
| `ComparisonError`, chart version not found | The pinned version was removed from the Helm repository | Pin a published version; never delete versions in use |
| A change made with `kubectl edit` disappears | Self-heal | Make the change in git |
| A retired object is still on the cluster | The bootstrap app does not prune | Delete it by hand after approval |

## Workloads

| Symptom | Cause | Fix |
|---|---|---|
| `CreateContainerConfigError: couldn't find key …` | A ConfigMap or Secret key the chart reads is missing in that namespace | Add it to the module's configuration (env file or secrets file) |
| `ErrImagePull` with an unexpected tag | The chart used its `appVersion` (image-tag mode), or the tag does not exist | Set the image-tag mode; check the tag exists for the application and migration images |
| Init container fails: migration checksum mismatch | Migrations from a different build ran earlier | Stop; compare builds; decide with the service owner (see [09](09-sop-and-guardrails.md#databases-and-migrations)) |
| Migration fails: "relation … already exists" or "applied migration not resolved locally" | The service migrates into a shared schema used by another service | Point it at its own schema |
| Application fails to start: "The server does not support SSL" | The application requires TLS to a database that does not offer it | Set the application's SSL mode for that database |
| `UnknownHostException` for a dependency | The service-host address names a service that does not exist | Point the key at the running service, or give the application its own key |
| Liveness/readiness probes fail with 404 | The probe path repeats the context path | Make the probe path relative to the context |
| Requests return 404 through the gateway | No route for the path in the API gateway | Add the route |

---

<sub>← Previous: [SOP and Guardrails](09-sop-and-guardrails.md) &nbsp;|&nbsp; [Contents](README.md) &nbsp;|&nbsp; Next: [Glossary](11-glossary.md) →</sub>
