# Sync Code Build workflow

`reusable-code-build-sync.yaml` keeps **both** Code Build dropdowns current, in one
place, and commits any change straight to the default branch via the GitHub App.

| Dropdown | Source | Update rule |
|---|---|---|
| `service` | `build/build-config.yml` (app `image-name`s, `-db` excluded) | **additive union** — adds/keeps, never drops (prune by hand) |
| `build_branch` | the repo's **live branches** (default first, `dependabot/*` excluded) | **replaced** each run, so deleted branches disappear |

Because `build_branch` is a synced `choice`, the native Run dialog shows a branch
**dropdown** instead of a text box.

## Trigger

The consumer's `sync-code-build.yaml` runs it when the config changes, when a
branch is created or deleted, on a daily backstop, and on demand:

```yaml
on:
  push:
    branches: [master]            # default branch only
    paths: ["build/build-config.yml"]
  create:                         # branch created
  delete:                         # branch deleted
  schedule:
    - cron: "17 3 * * *"          # daily backstop
  workflow_dispatch:
    inputs:
      sync_branch: { type: string, default: "" }
jobs:
  sync:
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-code-build-sync.yaml@reusable-build-v1
    with:
      sync_branch: ${{ inputs.sync_branch || '' }}
    secrets:
      APP_ID: ${{ secrets.BUILD_APP_ID }}
      APP_PRIVATE_KEY: ${{ secrets.BUILD_APP_PRIVATE_KEY }}
```

Every run syncs both lists; whichever is unchanged is a no-op. The workflow always
operates on the **default branch** regardless of which ref triggered it (so
`create`/`delete` events, which carry the new/old ref, still edit the right file).
No loop: it edits `code-build.yaml`, which is not a trigger path.

## Inputs

| Input | Default | Purpose |
|---|---|---|
| `config_path` | `build/build-config.yml` | Build config to read |
| `sync_branch` | `""` | Read the config from this branch (**Sync from Branch**, see below) |
| `workflow_file` | `.github/workflows/code-build.yaml` | Workflow whose lists are synced |
| `branch_exclude` | `^dependabot/` | ERE of branch names to leave out of the dropdown |
| `max_branches` | `200` | Cap on listed branches (GitHub limits choice options) |

Secrets: `BUILD_APP_ID` + `BUILD_APP_PRIVATE_KEY` (GitHub App with Contents +
Workflows write, on the default-branch ruleset bypass list).

## Sync from Branch

`sync_branch` ("Sync from Branch") lets a manual run read `build-config.yml` from
**another branch** and add its new **services** to the default branch's dropdown
*before* that branch merges — so the `/actions` UI (which dispatches on the default
branch, where `service` is validated) can build the new service on its branch. The
service union stays additive: it only adds, never removes.
