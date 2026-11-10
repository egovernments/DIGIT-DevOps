# Setup workflow

> This is the reference for the **Setup workflow** and the **GitHub App** it uses. For
> the end-to-end steps to put a new repo on Code Build, follow the
> [onboarding runbook](onboarding.md).

`reusable-setup.yaml` runs in two modes:

- **`full`** — scaffolds the Code Build caller (with the service + branch dropdowns
  populated) and the Trivy dashboard toolkit, **commits them straight to the default
  branch**, and publishes the **landing page** + `/actions` dispatcher UI to
  `gh-pages` (created if absent, Pages best-effort enabled).
- **`sync`** — **only** refreshes the Code Build dropdowns: the service list (additive
  union from `build-config.yml`, never drops) and the branch lists (from live
  branches). No scaffold, no Pages. This replaces the old separate **Build — Sync**
  workflow — run it manually from the Actions tab whenever branches/services change.

> Setup authenticates as a **GitHub App** and pushes directly to the default branch.
> The App must be on that branch's ruleset **bypass** list.

## 1. Create the GitHub App

The automatic `GITHUB_TOKEN` **cannot write files under `.github/workflows/`**, so
Setup uses a GitHub App token (minted in-run). Create one App for the org
(reused across consumers):

**Org → Settings → Developer settings → GitHub Apps → New GitHub App**

| Setting | Value |
|---|---|
| Repository permission · **Contents** | Read and write |
| Repository permission · **Workflows** | Read and write |
| Repository permission · **Pages** | Read and write *(auto-enable Pages)* |
| Repository permission · **Metadata** | Read-only *(mandatory, auto)* |

No **Pull requests** permission is needed — the flow pushes directly, it never
opens PRs.

Then:

1. **Install** the App on the consumer repo(s).
2. Generate a **private key** (`.pem`).
3. Add the App to the default branch's **ruleset bypass list**
   (Settings → Rules → Rulesets → the active ruleset → *Bypass list* → add the
   App → *Always*). Without this, protection blocks the App's push.
4. Store the credentials as repo secrets:

```sh
# the App's Client ID (Iv..), from the App's settings page — not the numeric App ID
gh secret set BUILD_APP_CLIENT_ID   --repo <owner>/<repo> --body "<client-id>"
gh secret set BUILD_APP_PRIVATE_KEY --repo <owner>/<repo> < private-key.pem
```

## 2. Add the caller and run it

`.github/workflows/setup.yaml` in the consumer:

```yaml
name: Build — Setup
on:
  workflow_dispatch:
    inputs:
      mode:                      # full = provision/upgrade; sync = only refresh dropdowns
        type: choice
        options: [full, sync]
        default: full
      sync_branch:               # sync mode: pull a branch's new services into the dropdown
        type: choice
        default: master
        options: [master]
      auth_mode:                 # full mode: /actions sign-in method
        type: choice
        options: [PAT, OAuth]    # PAT = paste a token (default); OAuth = Sign in with GitHub
        default: PAT
jobs:
  setup:
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-setup.yaml@reusable-build-v1
    with:
      mode: ${{ inputs.mode }}
      sync_branch: ${{ inputs.sync_branch }}
      auth_mode: ${{ inputs.auth_mode }}
    secrets:
      APP_CLIENT_ID: ${{ secrets.BUILD_APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.BUILD_APP_PRIVATE_KEY }}
```

Run it from the Actions tab (leave **Use workflow from** on the default branch —
setup refuses any other).

- **`mode: full`** commits `code-build.yaml` (dropdowns populated from
  `build-config.yml`), `.trivy/dashboard/` and `setup.yaml` directly to the default
  branch, and publishes the landing page (`/`) + `/actions` UI to `gh-pages`.
- **`mode: sync`** touches only the dropdowns in `code-build.yaml` (service union +
  branch list) and the `sync_branch` picker, commits if anything changed, and does
  nothing else. Use **`sync_branch`** to pull a feature branch's new services into the
  dropdown before it merges; leave it on the default branch for a normal refresh.

**`auth_mode`** (full mode) picks how the `/actions` UI signs in: **`PAT`** (default,
paste a fine-grained token) or **`OAuth`** ("Sign in with GitHub" via the shared broker
Worker — see [OAuth / broker Worker](oauth-worker.md), which must be deployed once,
with its URL baked into the page as `AUTH_BASE`). Setup **remembers your last pick** —
it rewrites `default:` in this repo's own `setup.yaml` — so the dropdown pre-selects it
next time. Re-run Setup to switch modes. Note: the first run after adopting this adds
the `mode`/`auth_mode` choices to the consumer's own `setup.yaml`, so they are available
from the **second** run onward.

## 3. Build prerequisites

Ensure the consumer has `DOCKER_USERNAME` (Actions **variable**) and
`DOCKER_ACCESS_TOKEN` (Actions **secret**).

Optionally set **`TRIVY_SCAN_BRANCHES`** (Actions **variable**) — the branches that get
Trivy-scanned and gated, one per line (e.g. `master`, `develop`). Branches not listed
build + push unscanned. If unset, only the default branch is scanned. See
[build.md](build.md#scan-policy).

## Notes

- Re-running setup is safe; it commits only what changed (nothing if in sync).
- If the App lacks `Pages:write`, enable Pages manually (Settings → Pages → `gh-pages`).
- If the push fails with a protection error, the App is not on the ruleset bypass list.
