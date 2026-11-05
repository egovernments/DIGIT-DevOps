# Setup workflow

> This is the reference for the **Setup workflow** and the **GitHub App** it uses. For
> the end-to-end steps to put a new repo on Code Build, follow the
> [onboarding runbook](onboarding.md).

`reusable-setup.yaml` provisions a consumer repo in one run: it scaffolds the
Code Build caller (with the service + branch dropdowns already populated), the sync-code-build
workflow and the Trivy dashboard toolkit, and **commits them straight to the
default branch**. It also publishes a **landing page** and the `/actions`
dispatcher UI to `gh-pages` (created if absent) and best-effort enables Pages.

> Setup and sync authenticate as a **GitHub App** and push directly to the
> default branch. The App must be on that branch's ruleset **bypass** list.

## 1. Create the GitHub App

The automatic `GITHUB_TOKEN` **cannot write files under `.github/workflows/`**, so
setup and sync use a GitHub App token (minted in-run). Create one App for the org
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
      auth_mode:                 # Code Build /actions sign-in method
        type: choice
        options: [PAT, OAuth]    # PAT = paste a token (default); OAuth = Sign in with GitHub
        default: PAT
jobs:
  setup:
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-setup.yaml@reusable-build-v1
    with:
      auth_mode: ${{ inputs.auth_mode }}
    secrets:
      APP_CLIENT_ID: ${{ secrets.BUILD_APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.BUILD_APP_PRIVATE_KEY }}
```

Run it from the Actions tab (leave **Use workflow from** on the default branch —
setup refuses any other). It commits `code-build.yaml` (dropdowns populated from
`build-config.yml`), `sync-code-build.yaml`, `.trivy/dashboard/` and `setup.yaml`
directly to the default branch, and publishes the landing page (`/`) + `/actions`
UI to `gh-pages`.

**`auth_mode`** picks how the `/actions` UI signs in: **`PAT`** (default, paste a
fine-grained token) or **`OAuth`** ("Sign in with GitHub" via the shared broker
Worker — see [OAuth / broker Worker](oauth-worker.md), which must be deployed
once, with its URL baked into the page as `AUTH_BASE`). Setup **remembers your last
pick** — it rewrites `default:` in this repo's own `setup.yaml` — so the dropdown
pre-selects it next time. Re-run Setup to switch modes.
Note: the first run after adopting this adds the `auth_mode` choice to the consumer's
own `setup.yaml`, so picking `OAuth` is available from the **second** run onward.

## 3. Build prerequisites

Ensure the consumer has `DOCKER_USERNAME` (Actions **variable**) and
`DOCKER_ACCESS_TOKEN` (Actions **secret**).

## Notes

- Re-running setup is safe; it commits only what changed (nothing if in sync).
- If the App lacks `Pages:write`, enable Pages manually (Settings → Pages → `gh-pages`).
- If the push fails with a protection error, the App is not on the ruleset bypass list.
