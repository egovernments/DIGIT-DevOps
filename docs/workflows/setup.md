# Setup workflow

`reusable-setup.yml` provisions a consumer repo in one run: it scaffolds the
Code Build caller, the sync-dropdown workflow, the Trivy dashboard toolkit and
the `/pipelines` UI, creates `gh-pages`, then syncs the dropdowns.

## 1. Create the `WORKFLOWS_TOKEN`

The automatic `GITHUB_TOKEN` **cannot write files under `.github/workflows/`**, so
setup and sync need a token with `Workflows:write`. GitHub has no API to mint a
token — create it in the browser:

**Settings → Developer settings → Fine-grained tokens → Generate new token**
(<https://github.com/settings/personal-access-tokens/new>)

| Setting | Value |
|---|---|
| Resource owner | `egovernments` |
| Repository access | Only select repositories → the consumer repo |
| **Contents** | Read and write |
| **Workflows** | Read and write |
| **Pages** | Read and write *(optional — lets setup auto-enable Pages)* |
| Expiration | per policy |

Add it as a repo secret:

```sh
# run yourself so the token value never leaves your machine:
gh secret set WORKFLOWS_TOKEN --repo <owner>/<repo>
```

> If the org requires approval for fine-grained tokens, an owner approves it once.

## 2. Add the caller and run it

`.github/workflows/setup.yml` in the consumer:

```yaml
name: Setup Code Build
on:
  workflow_dispatch:
jobs:
  setup:
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-setup.yml@feature/reusable-build-workflow
    secrets:
      WORKFLOWS_TOKEN: ${{ secrets.WORKFLOWS_TOKEN }}
```

Run it from the Actions tab. When it finishes the repo has `code-build.yml`,
`sync-dropdown.yml`, `.trivy/dashboard/`, `pipelines/` and a `gh-pages` branch,
and the dropdowns are populated from `build-config.yml`.

## 3. Build prerequisites

Ensure the consumer has `DOCKER_USERNAME` (Actions **variable**) and
`DOCKER_ACCESS_TOKEN` (Actions **secret**).

## Notes

- Re-running setup is safe; it only adds what is missing.
- If the token lacks `Pages:write`, enable Pages manually (Settings → Pages → `gh-pages`).
