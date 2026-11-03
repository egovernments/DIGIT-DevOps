# Reusable build workflows

Central CI library for eGov service repositories. A consumer repo keeps one thin
caller; everything else is provisioned from here and upgraded centrally.

## Workflows

| Workflow | Purpose |
|---|---|
| [`reusable-build.yaml`](build.md) | Build + push images, with Trivy code + image scans (CRITICAL blocks the push) |
| [`reusable-setup.yaml`](setup.md) | One-shot scaffold of a consumer repo (Code Build caller, sync, Trivy toolkit, `/pipelines` UI, gh-pages) |
| [`reusable-sync-dropdown.yaml`](sync-dropdown.md) | Keep the Code Build dropdowns current with `build-config.yml` (additive) |

## What a consumer ends up with

- `.github/workflows/code-build.yaml` — build caller with **module/service dropdowns**, synced from `build-config.yml`.
- `.github/workflows/sync-dropdown.yaml` — refreshes those dropdowns on config change.
- `.trivy/dashboard/` — Trivy report generator, published to `gh-pages/security/trivy`.
- `pipelines/index.html` — the [`/pipelines` dispatcher UI](pipelines-ui.md) (cascading branch → module → service).

## Onboard a repo

1. Create the `WORKFLOWS_TOKEN` secret (see [setup.md](setup.md)).
2. Add a one-line `setup.yml` caller and run it once.
3. Ensure the repo has `DOCKER_USERNAME` (variable) and `DOCKER_ACCESS_TOKEN` (secret).

Two ways to run a build afterwards:

- **GitHub-native** — Actions → **Code Build** → Run workflow (session auth, synced dropdowns).
- **`/pipelines` UI** — cascading, branch-driven, needs a scoped fine-grained PAT.

## Versioning

Callers pin a moving major tag `@reusable-build-v1` (or an immutable `@reusable-build-v1.x.y`).
Move the major tag to a new release commit to roll it out to every consumer.
