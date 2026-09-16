# Inji module Applications

One file per Application, numbered in bring-up order. Split out of a single
`inji-applications.yaml` deliberately: that file applied all eight modules at
once, which starts eight mostly-JVM pods simultaneously — before config-server
has any properties to serve, and onto a cluster that is already memory-tight.

ArgoCD does **not** order Applications. The sequence below is enforced only by
you applying these files in filename order and checking each one before moving
on. Nothing in the manifests will stop you skipping ahead.

## Sequence

| # | File | Why it is here |
|---|---|---|
| 1 | `01-config-server.yaml` | publishes `config-server-share`, read by 5, 6 and 7 |
| 2 | `02-artifactory.yaml` | publishes `artifactory-share`, read by 6 and 7 |
| 3 | `03-softhsm-esignet.yaml` | publishes `esignet-softhsm-share`, read by 5 |
| 4 | `04-softhsm-certify.yaml` | publishes `softhsm-certify-share`, read by 6 |
| 5 | `05-esignet.yaml` | the OIDC provider Certify authenticates against |
| 6 | `06-inji-certify.yaml` | the credential issuer |
| 7 | `07-mimoto.yaml` | wallet backend-for-frontend; cluster-internal only |
| 8 | `08-injiweb.yaml` | the web wallet UI |

Steps 3 and 4 are independent of each other and can go together. Everything
else is strictly sequential.

```bash
kubectl apply -f applications/01-config-server.yaml
kubectl -n argocd get application inji-config-server   # wait for Synced/Healthy
kubectl apply -f applications/02-artifactory.yaml
# ... and so on
```

## Prerequisites — none of these Applications create them

Applying step 1 before these are in place gives you a CrashLoopBackOff, not a
clear error:

- **Databases.** `inji-db-init` must have run green. Check:
  `kubectl exec -n egov postgres-0 -- psql -U postgres -tAc "select datname from pg_database where datname like 'inji%' or datname='mosip_esignet';"`
- **`inji-stack-config`.** The local chart, enabled in `test-lts.yaml`. Read by
  6, 7 and 8 via `extraEnvVarsCM`.
- **Config properties.** `deploy-as-code/inji-config/` populated, and
  config-server's `envVariables` list resolved. 5, 6 and 7 will not start
  without it. 8 does not read config-server.
- **`google-client` secret.** Mimoto references it unconditionally — step 7
  fails with `CreateContainerConfigError` without it, even if Google sign-in
  is unused.
- **`mimotooidc` secret** (`oidckeystore.p12`) for step 7.
- **Cluster capacity.** These are ~8 additional mostly-JVM pods.
- **DNS.** A records for `injiweb.`, `injicertify.`, `esignet.` before enabling
  the matching `inji-ingress.modules.*` flag.

## Notes that apply to every file

- **`istio.enabled: false`** in every values file. All the upstream charts route
  solely through Istio (`gateway.yaml` / `virtualservice.yaml`, both gated on
  that flag) and render no Kubernetes Ingress. digit-lts has no Istio; routing
  comes from the local `inji-ingress` chart.
- **`helm.releaseName` is load-bearing.** `esignet`, `inji-certify`, `mimoto`
  and `injiweb` have no `fullnameOverride` support, so their Service name comes
  from the release name — and those names are what `inji-ingress` and injiweb's
  templated nginx proxy target. `config-server`, `artifactory` and `softhsm` do
  support `fullnameOverride`, which is how their `*-share` ConfigMaps get the
  exact names their consumers expect.
- **Charts come from `https://mosip.github.io/mosip-helm` at pinned versions**,
  with values from this repo via the `$values` ref — the same multi-source
  pattern as `monitoring-applications.yaml`. Nothing is vendored, so a version
  bump is a `targetRevision` change.
