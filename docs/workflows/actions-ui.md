# CI pages: landing page + /actions dispatcher

Setup publishes a small static site to the consumer's `gh-pages` branch:

| Path | Page |
|---|---|
| `/` | **Landing page** — cards linking to each tool (Code Build, Security, the Actions tab, the repo). |
| `/actions/` | **Code Build dispatcher** — triggers a build with a live **branch → service** picker. |
| `/security/trivy/` | **Trivy dashboard** — scan reports, published by the build. |

The landing page derives the owner/repo from the Pages URL, so it is generic
across consumers. Open it at `https://<owner>.github.io/<repo>/`.

## The /actions dispatcher

`/actions/` is a self-contained page that triggers **Code Build** with a live
**branch → service** selection read from the chosen branch's `build-config.yml`.
It runs with no server — talking straight to `api.github.com`.

### Two doors, one workflow

| Door | Auth | Picker |
|---|---|---|
| GitHub-native Run workflow | github.com session | synced **dropdowns** (`build_branch` + `service`), kept current by sync-code-build |
| `/actions` UI | fine-grained PAT | live branch **dropdown**; services read from the chosen branch |

Both dispatch the same `code-build.yaml`. The native dialog's lists are synced
snapshots; the UI reads branches and each branch's services **live**, so it can
also surface a service that exists only on a not-yet-merged feature branch.

### Authentication

A **fine-grained PAT**, held **in memory for the tab only** — never stored, cleared
after 15 min idle, and (via a strict CSP) only ever able to reach `api.github.com`.

| Setting | Value |
|---|---|
| Repository access | the consumer repo |
| Contents | Read |
| Actions | Read and write |
| Expiration | short (7–30 days) |

This is a **small, separate** token: it only reads config and dispatches builds —
it cannot write code or workflows (unlike the setup GitHub App).

### Flow

1. **Read** branches, then the chosen branch's `build-config.yml`.
2. **Pick** branch → service (with a resolved image/dockerfile/db preview).
3. **Dispatch** `workflow_dispatch` to `code-build.yaml` on the **default branch**, passing the chosen branch as `build_branch` + `service`. (The workflow lives only on the default branch; the engine checks out `build_branch` to build it.)
4. **Watch** the run (polled) with a link, and jump to its `/security/trivy` report.

## Hosting

Private repos need a token even to read config, so the page is inert without one;
a hosted copy exposes nothing. Setup enables Pages (branch `gh-pages`) for the
shared URL automatically.
