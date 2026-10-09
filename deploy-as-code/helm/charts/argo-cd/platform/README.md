# platform/ — Keycloak and Vault on digit-lts

Argo CD wiring for the two shared platform services on the Azure AKS
**digit-lts** environment (`test-lts.digit.org`).

| File | What it is |
|---|---|
| `platform-app-project.yaml` | AppProject `platform-project` — namespaces `keycloak` and `vault-new` |
| `applications/01-keycloak.yaml` | Application `platform-keycloak` |
| `applications/02-vault.yaml` | Application `platform-vault` |

## This is an adoption, not an install

Both workloads were **already running and were not created by Argo CD**:

| | Keycloak | Vault |
|---|---|---|
| Namespace | `keycloak` | `vault-new` (not `vault`) |
| Age | ~84 days | ~81 days |
| Argo CD tracking-id | none | none |
| Helm release metadata | none at all | `managed-by: Helm` label, but no release Secret |
| Image | `egovio/keycloak:keycloak-spi-custom-build-aardhya-78019f9` (custom eGov SPI build) | `hashicorp/vault:1.18.1`, `hashicorp/vault-k8s:1.6.2` |

Because of that, the values in both Applications were **written from what the
cluster actually has**, not from chart defaults. Each override exists because
the chart default differed from live and would have caused a change on sync.

## Verified state

Rendered with the same values Argo CD will use and diffed against the live
cluster. Remaining differences, both covered by `ignoreDifferences`:

| Application | Remaining diff | Why it is safe |
|---|---|---|
| `platform-keycloak` | pod annotation `deployment-timestamp` | Injected by eGov's pipeline, not rendered by the chart. Ignored, so the resource computes as Synced and (with `ApplyOutOfSyncOnly=true`) is never applied. |
| `platform-vault` | webhook `caBundle` | Written by the injector at runtime; the chart renders it empty. Ignored so a sync cannot blank it. |

Also confirmed: **no rendered object is missing from the cluster**, so a sync
creates nothing new in either namespace.

## The overrides, and what each prevents

### Keycloak

- **`KC_DB_URL` → `postgres.egov`.** The chart default *used to* point at
  `postgresql-lts.egov`, the instance being decommissioned — on its own an
  auth outage waiting to happen. **Fixed at source:**
  `charts/core-services/keycloak/values.yaml` now defaults to `postgres.egov`,
  so the chart and the live cluster agree and this override merely restates
  it. (`digit-lts.yaml` and `digit-health-lts.yaml` still reference
  `postgresql-lts`, but both are stale environment files and neither defines
  a `keycloak:` block.)
- **`env` is NOT overridden — and must not be.** An earlier version of this
  Application replaced the whole `env` block with the live 34 entries. That
  worked, but it was a trap: the chart stores `env` as a **scalar string**
  (`env: |`), and Helm *replaces* scalars instead of merging them, so the
  override silently discarded anything anyone later added to the chart
  values — no error, no effect. Measured: 42 env vars rendered from the chart,
  34 after the override, the addition gone.

  **Fixed at source instead.** `charts/core-services/keycloak/values.yaml` now
  reproduces the live env exactly (34 entries, same order, same values,
  verified against the running pod), so no override is needed and chart
  additions flow through normally. Three chart changes made that possible:
  - **Added the 7 missing vars.** `KC_HOSTNAME` / `KC_HOSTNAME_STRICT` (losing
    them breaks issuer URLs and OIDC discovery behind the ingress) and the five
    OTP registration/default settings. `KC_HOSTNAME` is derived from
    `global.domain`, so it is right per environment rather than pinned.
  - **`OTP_HOST` switched from `configMapKeyRef` to a literal.** The ConfigMap
    key `egov-service-host/otp` resolves to `http://otp.egov:8080/`, and the
    `otp` Service **has no endpoints** on digit-lts — the working backend is
    `otp-java`. It also caused an apply-blocking conflict: `env` lists
    strategic-merge **by name**, so a chart using `valueFrom` against a live
    object using `value` yields an entry with both keys and the API server
    rejects it (`env[N].valueFrom: may not be specified when 'value' is not
    empty`). Override with `otp-host` where the service name differs.
  - **Telemetry block gated** on `tracing-enabled` / `metrics-enabled`, so a
    deployment with tracing off gets none of those vars rather than a set
    reading `"false"` — 8 env vars the running pod does not have, i.e. a
    guaranteed rollout. Both paths verified: off → 34 vars, on → 48.
- **`tracing-enabled: false` as a BOOLEAN.** The common chart gates its Jaeger
  block on `if or (global.tracing-enabled) (tracing-enabled)`, and in Helm a
  non-empty **string** is truthy — so `"false"` still injects six
  `JAEGER_*`/`TRACER_*` env vars. (The chart's own `values.yaml` uses the
  string form, which is why its default renders Jaeger even when "disabled".)
- **Resources** raised to the live `1` CPU / `2Gi` limits; chart defaults would
  halve the memory limit and restart the pod.
- **`serviceMonitor.enabled: false`** — there is no ServiceMonitor in the
  `keycloak` namespace today. `test-lts.yaml` turns tracing, metrics and the
  ServiceMonitor all on, which is why all three are forced back off here.

### Vault

- **`releaseName: release-name`.** Not a placeholder. The live release was
  installed under that literal name, so both workloads carry
  `app.kubernetes.io/instance: release-name` in their **immutable**
  `spec.selector`. Any other release name fails with
  `spec.selector: field is immutable` and would require deleting and
  recreating the StatefulSet. This is the same pathology that broke
  cert-manager on this cluster, and the reason the backbone appset
  deliberately omits kafka.
- **Ingress host → `test-lts.digit.org`.** The chart hard-codes
  `digit-lts.digit.org`; syncing unfixed would replace a working Ingress with
  one for a hostname that does not resolve here and send cert-manager into a
  doomed HTTP01 challenge (failures burn Let's Encrypt rate limit).
- **`server.ha.raft.config`** replaced with the live config — the chart adds
  two `telemetry` stanzas the live ConfigMap does not have. Vault reads its
  config only at startup, so changing it implies a restart.

## Before you turn on automated sync

Neither Application has a `syncPolicy.automated` block. That is deliberate:
adopting a hand-managed workload is the one case where `selfHeal` can cause
the very outage it is meant to prevent.

1. Apply the AppProject, then the two Applications (see below).
2. Confirm both report **Synced** without being synced.
3. Only then consider adding `automated`.

Once automated sync is on, **these values become the source of truth** — if
someone edits the live Deployment by hand, Argo CD reverts it to what is
written here.

## Applying

`charts/argo-cd/` is the bootstrap seam: it is **not** itself managed by Argo
CD, so these are applied directly. The AppProject must exist first, or the
Applications are rejected with *"application destination is not permitted in
project"*.

```bash
kubectl apply -f platform-app-project.yaml
kubectl apply -f applications/01-keycloak.yaml
kubectl apply -f applications/02-vault.yaml
```

Neither Application carries `resources-finalizer.argocd.argoproj.io`, so
deleting one stops tracking rather than cascade-deleting a live workload —
the failure mode that lost the backbone elasticsearch StatefulSets.

## Notes for later

- **Vault auto-unseals.** It uses Azure Key Vault
  (`vault_name = digit-lts-vault-unseal`), not Shamir, so a restarted pod
  unseals itself provided the Azure identity still has access to that key.
  There are no manual unseal keys to hold. A restart is still a brief outage.
- **The `vault:` block in `test-lts.yaml` is ignored.** The HashiCorp chart
  does not use the `common` library, so that block never reaches the chart.
  Anything real has to be set in the Application's inline `values`.
- **Editing Vault's `config` string:** no comments inside it (they land
  verbatim in the ConfigMap as drift) and no Go-template syntax beyond the
  seal conditionals already present (the chart runs it through `tpl`, so a
  stray `{{ ... }}` fails the whole render).
- Both Applications use `environments/test-lts.yaml`, not `digit-lts.yaml`.
  Only test-lts matches this cluster.
