# Sync-dropdown workflow

`reusable-sync-dropdown.yaml` keeps the **Code Build** dropdowns in step with
`build-config.yml`.

## What it does

- **Services** = every app `image-name` in the config (entries ending `-db` are excluded).
- **Modules** = the 3rd path segment of each job `name`
  (`builds/<repo>/<module>/<service>`).
- It writes these into the `module` and `service` `choice` option lists of
  `code-build.yaml`, as an **additive union**: new entries are added, existing ones
  are kept. Nothing is removed (the scaffold `placeholder` seed is the one
  exception). A service removed from the config stays selectable until pruned by hand.
- Changes are delivered as a **`chore: sync Code Build dropdowns` PR** (updated in
  place on re-runs), never pushed to a protected branch.

## Trigger

The consumer's `sync-dropdown.yaml` runs it on push to `build/build-config.yml`
and on demand:

```yaml
on:
  push:
    paths: ["build/build-config.yml"]
  workflow_dispatch:
jobs:
  sync:
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-sync-dropdown.yaml@reusable-build-v1
    secrets:
      WORKFLOWS_TOKEN: ${{ secrets.WORKFLOWS_TOKEN }}
```

## Inputs

| Input | Default | Purpose |
|---|---|---|
| `config_path` | `build/build-config.yml` | Build config to read |
| `workflow_file` | `.github/workflows/code-build.yaml` | Workflow whose options are synced |

Secret: `WORKFLOWS_TOKEN` (Contents + Workflows + Pull requests write).

## Per-branch behaviour

The sync commits to the branch that changed the config, and `workflow_dispatch`
reads inputs from the selected branch — so a service added on a feature branch
appears in that branch's dropdowns (and becomes dispatchable from the UI) once the
sync has run there. No loop: the sync edits `code-build.yaml`, which is not a
trigger path.
