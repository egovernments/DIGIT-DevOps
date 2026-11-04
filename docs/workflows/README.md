# Reusable build workflows

Central CI library for eGov service repositories. A consumer repo keeps one thin
caller; everything else is provisioned from here and upgraded centrally.

## Workflows

| Workflow | Purpose |
|---|---|
| [`reusable-build.yaml`](build.md) | Build + push images, with Trivy code + image scans (CRITICAL blocks the push) |
| [`reusable-setup.yaml`](setup.md) | One-shot scaffold of a consumer repo (Code Build caller, sync, Trivy toolkit, gh-pages landing page + `/actions` UI) |
| [`reusable-sync-dropdown.yaml`](sync-dropdown.md) | Keep the Code Build dropdowns current with `build-config.yml` (additive) |
| `promote-reusable-tag.yaml` | Auto-move `reusable-build-v1` to master when the engine/templates change (not reusable; runs in this repo) |

## What a consumer ends up with

- `.github/workflows/code-build.yaml` — build caller with a **service dropdown**, synced from `build-config.yml`, plus a **Build from Branch** input.
- `.github/workflows/sync-dropdown.yaml` — refreshes that dropdown on config change.
- `.trivy/dashboard/` — Trivy report generator, published to `gh-pages/security/trivy` (scans gate the default branch only).
- gh-pages **landing page** (`/`) + [`/actions` dispatcher UI](actions-ui.md) (live branch → service picker).

## Onboard a repo

1. Create the GitHub App + its secrets (see [setup.md](setup.md)).
2. Add a one-line `setup.yaml` caller and run it once.
3. Ensure the repo has `DOCKER_USERNAME` (variable) and `DOCKER_ACCESS_TOKEN` (secret).

Two ways to run a build afterwards:

- **GitHub-native** — Actions → **Code Build** → Run workflow (session auth, synced dropdown).
- **`/actions` UI** — live branch picker, needs a scoped fine-grained PAT.

## Versioning

Callers pin a moving major tag `@reusable-build-v1` (or an immutable `@reusable-build-v1.0.y`).

The move is **automated**: `promote-reusable-tag.yaml` runs when `reusable-*.yaml`
or `templates/consumer/**` change on master, repoints `reusable-build-v1` at the
new master tip, and cuts the next immutable `reusable-build-v1.0.<N>` snapshot. So
merging a change here rolls it out to every consumer with no manual tag move. (It
can also be run from the Actions tab via **Run workflow**.) Cut a new major tag
`reusable-build-v2` by hand for a breaking change.
