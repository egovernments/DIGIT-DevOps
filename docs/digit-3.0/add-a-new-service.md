# Runbook: add a new service to an existing product

Use this to add one service to a product that already exists (for example adding a new service to
`core-3.0`). This is much smaller than adding a whole product: in most cases it is two edits.

Read [README.md](README.md) and [structure.md](structure.md) first if you have not.

> Replace `<module>` with the product's dotted name (`core-3.0`), `<ns>` with its namespace
> (`core-3-0`), and `<service>` with the new service's chart name.

## Before you begin - confirm these facts

1. **The chart exists and its name.** Open `https://helm.digit.org/digit3/<module-repo>/index.yaml`
   and confirm `<service>` is listed. Note its newest version. The chart name is what you use
   everywhere below.
2. **Does it have a database migration image?** DIGIT services that own database tables ship a
   companion `<service>-db` image and set `dbMigration: true`. If unsure, check how similar
   services in the same Kargo project file are configured.
3. **Which layout?** Almost always `common` (a standard DIGIT service). Use `root` only for a
   third-party-style chart that expects plain top-level values. Use `configs` only for
   cluster-configs. If every other service in the project uses the project's default layout and
   this one is ordinary, you do not set a layout at all.
4. **Does it need a public route?** If yes, it gets `ingress.enabled: true` in the values file and
   its route is reachable at `https://<product>-3.unified-dev.digit.org/<path>`.

## Step 1 - Add the service to the Kargo project file

Edit `charts/kargo/config/projects/<ns>.yaml` and add an entry to `kargo.services`. Copy an
existing similar entry and change the name:

```yaml
    - name: <service>
      chart: <service>
      dbMigration: true          # omit or set false if the service has no <service>-db image
      freightCreationPolicy: Manual
      imageSelectionStrategy: NewestBuild
      cacheByTag: true
      discoveryLimit: 20
      interval: 5m0s
      # deploy:                   # only if it is not the project's default layout
      #   layout: root
```

That is all it takes for Argo CD to create the `digit3-<service>` Application - the kargo-managed
ApplicationSets read this list. **Do not create an Application by hand.**

> **Guardrail (Rule 7):** you never write or edit a service Application or a kargo-managed
> ApplicationSet directly. The single source of truth for "which services exist" is this list.

## Step 2 - Add the service's settings to the values file

Edit `environments/digit-3.0/<module>.yaml` and add a top-level section for the service:

```yaml
<service>:
  chart-version: "<newest-from-index>"   # or leave to the first promotion to merge in
  ingress:
    enabled: true                         # only if it needs a public route
  # ... any service-specific settings ...
```

If the service needs secret values, add them to `environments/digit-3.0/<module>-secrets.yaml`
through SOPS (never plaintext).

> **Guardrail (Rule 6):** take `chart-version` from the published index
> (`helm.digit.org/digit3/<module-repo>/index.yaml`), newest first. Do not guess.
>
> **Guardrail (Rule 5):** the module should already be `global.mode: prod`, so the service uses the
> released image baked into its chart automatically. You do not add an `image.tag`.

## Step 3 - Validate locally

```bash
# YAML valid
python3 -c "import yaml,sys; [list(yaml.safe_load_all(open(f))) for f in sys.argv[1:]]" \
  deploy-as-code/helm/environments/digit-3.0/<module>.yaml \
  deploy-as-code/helm/charts/kargo/config/projects/<ns>.yaml

# the service now appears exactly once in the project's service list
grep -n "name: <service>" deploy-as-code/helm/charts/kargo/config/projects/<ns>.yaml
```

## Step 4 - Open a pull request

Commit only the two (or three, with secrets) files you edited. Open a pull request against
`unified-dev`, describing the service and its chart version. **Stop. A person merges.**

## Step 5 - After the merge

1. In Kargo, the new service's Warehouse appears and discovers versions. Assemble Freight and
   promote it to dev (see [operate-argocd-and-kargo.md](operate-argocd-and-kargo.md)). The first
   promotion merges `chart-version` and `image.tag` into the values file (if you did not seed
   them).
2. Confirm the `digit3-<service>` Application is **Synced / Healthy** and the pods are running in
   `<ns>`.
3. If it has a route, confirm `https://<product>-3.unified-dev.digit.org/<path>` answers (a
   protected route returns 401; 404/502 means the route or service is not up yet).

## Common mistakes (and the rule they break)

- Editing a kargo-managed ApplicationSet to "add" the service -> breaks **Rule 7**. Add it to the
  Kargo project file instead.
- Putting the service's settings in `unified-dev.yaml` -> breaks **Rule 4**. They go in the
  module's own values file.
- Setting an `image.tag` to pick a build while `mode: prod` -> the tag is ignored (that is by
  design); if you truly need a specific unreleased build, that is a deliberate `dev`-mode decision,
  not a routine service addition.
- Guessing the chart version -> breaks **Rule 6**. Read the published index.
