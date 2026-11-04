# /pipelines dispatcher UI

`pipelines/index.html` is a self-contained page that triggers **Code Build** with
cascading **branch → module → service** selection read live from the chosen
branch's `build-config.yml`.

It runs with no server — opened locally (`file://`), from GitHub Pages, or any
static host — talking straight to `api.github.com`.

## Two doors, one workflow

| Door | Auth | Dropdowns |
|---|---|---|
| GitHub-native Run workflow | github.com session | synced `choice` lists |
| `/pipelines` UI | fine-grained PAT | live, cascading, branch-driven |

Both dispatch the same `code-build.yaml`.

## Authentication

A **fine-grained PAT**, held **in memory for the tab only** — never stored, cleared
after 15 min idle, and (via a strict CSP) only ever able to reach `api.github.com`.

| Setting | Value |
|---|---|
| Repository access | the consumer repo |
| Contents | Read |
| Actions | Read and write |
| Expiration | short (7–30 days) |

This is a **different, smaller** token than `WORKFLOWS_TOKEN`: it only reads config
and dispatches builds — it cannot write code or workflows.

## Flow

1. **Read** branches, then the branch's `build-config.yml`.
2. **Cascade** module → service (filtered), with a resolved image/dockerfile/db preview.
3. **Dispatch** `workflow_dispatch` to `code-build.yaml` on the **default branch**, passing the chosen branch as `build_branch` + `service`. (The workflow lives only on the default branch; the engine checks out `build_branch` to build it.)
4. **Watch** the run (polled) with a link.

## Security tab

Links to the gh-pages `/security/trivy` dashboard produced by the build.

## Hosting

Private repos need a token even to read config, so the page is inert without one;
a hosted copy exposes nothing. Enable Pages (branch `gh-pages`) for a shared URL,
or just open `pipelines/index.html` locally.
