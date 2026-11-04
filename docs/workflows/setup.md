# Setup workflow

`reusable-setup.yaml` provisions a consumer repo in one run: it scaffolds the
Code Build caller (with the service dropdown already populated), the sync-dropdown
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
gh secret set BUILD_APP_ID          --repo <owner>/<repo> --body "<app-id>"
gh secret set BUILD_APP_PRIVATE_KEY --repo <owner>/<repo> < private-key.pem
```

## 2. Add the caller and run it

`.github/workflows/setup.yaml` in the consumer:

```yaml
name: Setup Code Build
on:
  workflow_dispatch:
jobs:
  setup:
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-setup.yaml@reusable-build-v1
    secrets:
      APP_ID: ${{ secrets.BUILD_APP_ID }}
      APP_PRIVATE_KEY: ${{ secrets.BUILD_APP_PRIVATE_KEY }}
```

Run it from the Actions tab (leave **Use workflow from** on the default branch —
setup refuses any other). It commits `code-build.yaml` (dropdowns populated from
`build-config.yml`), `sync-dropdown.yaml`, `.trivy/dashboard/` and `setup.yaml`
directly to the default branch, and publishes the landing page (`/`) + `/actions`
UI to `gh-pages`.

## 3. Build prerequisites

Ensure the consumer has `DOCKER_USERNAME` (Actions **variable**) and
`DOCKER_ACCESS_TOKEN` (Actions **secret**).

## Notes

- Re-running setup is safe; it commits only what changed (nothing if in sync).
- If the App lacks `Pages:write`, enable Pages manually (Settings → Pages → `gh-pages`).
- If the push fails with a protection error, the App is not on the ruleset bypass list.
