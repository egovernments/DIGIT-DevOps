# Sync-dropdown workflow

`reusable-sync-dropdown.yaml` keeps the **Code Build** service dropdown in step with
`build-config.yml`.

## What it does

- **Services** = every app `image-name` in the config (entries ending `-db` are excluded).
- It writes these into the `service` `choice` option list of
  `code-build.yaml`, as an **additive union**: new entries are added, existing ones
  are kept. Nothing is removed (the scaffold `placeholder` seed is the one
  exception). A service removed from the config stays selectable until pruned by hand.
- Changes are **committed straight to the default branch** via the GitHub App
  (which is on that branch's ruleset bypass list).

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
      APP_ID: ${{ secrets.BUILD_APP_ID }}
      APP_PRIVATE_KEY: ${{ secrets.BUILD_APP_PRIVATE_KEY }}
```

## Inputs

| Input | Default | Purpose |
|---|---|---|
| `config_path` | `build/build-config.yml` | Build config to read |
| `sync_branch` | `""` | Read the config from this branch (empty = this/default branch) |
| `workflow_file` | `.github/workflows/code-build.yaml` | Workflow whose options are synced |

Secrets: `BUILD_APP_ID` + `BUILD_APP_PRIVATE_KEY` (GitHub App with Contents +
Workflows write, on the default-branch ruleset bypass list).

## Sync from Branch

Sync always runs **from the default branch** (enforced) and commits to it,
but `sync_branch` ("Sync from Branch") lets it read `build-config.yml` from **another
branch**. Use it to pull a feature branch's new services into the default branch's
dropdown *before* that branch merges — so the `/actions` UI (which dispatches on
the default branch) can build the new service on its branch. The union is still
additive: it only adds, never removes. No loop: the sync edits `code-build.yaml`,
which is not a trigger path.
