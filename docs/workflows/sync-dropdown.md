# Sync-dropdown workflow

`reusable-sync-dropdown.yaml` keeps the **Code Build** service dropdown in step with
`build-config.yml`.

## What it does

- **Services** = every app `image-name` in the config (entries ending `-db` are excluded).
- It writes these into the `service` `choice` option list of
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
    branches: [master]            # default branch only
    paths: ["build/build-config.yml"]
  workflow_dispatch:
    inputs:
      sync_branch:                # "Sync from Branch" (optional)
        type: string
        default: ""
jobs:
  sync:
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-sync-dropdown.yaml@reusable-build-v1
    with:
      sync_branch: ${{ inputs.sync_branch || '' }}
    secrets:
      WORKFLOWS_TOKEN: ${{ secrets.WORKFLOWS_TOKEN }}
```

## Inputs

| Input | Default | Purpose |
|---|---|---|
| `config_path` | `build/build-config.yml` | Build config to read |
| `sync_branch` | `""` | Read the config from this branch (empty = this/default branch) |
| `workflow_file` | `.github/workflows/code-build.yaml` | Workflow whose options are synced |

Secret: `WORKFLOWS_TOKEN` (Contents + Workflows + Pull requests write).

## Sync from Branch

Sync always runs **from the default branch** (enforced) and opens its PR against it,
but `sync_branch` ("Sync from Branch") lets it read `build-config.yml` from **another
branch**. Use it to pull a feature branch's new services into the default branch's
dropdown *before* that branch merges — so the `/pipelines` UI (which dispatches on
the default branch) can build the new service on its branch. The union is still
additive: it only adds, never removes. No loop: the sync edits `code-build.yaml`,
which is not a trigger path.
