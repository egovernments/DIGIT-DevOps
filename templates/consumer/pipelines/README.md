# Code Build dispatcher (`/pipelines`)

A self-contained page that triggers the **Code Build** workflow for any service in
`build/build-config.yml`, with cascading **branch → module → service** selection read
live from the chosen branch.

It is a single static file (`index.html`). It works three ways, with no server:

- opened locally (`file://`),
- served from GitHub Pages, or
- any static host.

All GitHub calls go straight to `api.github.com` from your browser.

## Authentication

The page uses a **fine-grained personal access token**, held **in memory for the tab
only** — it is never written to `localStorage`, `sessionStorage`, cookies, or disk, and a
strict Content-Security-Policy means it can only ever reach `api.github.com`. Close the
tab (or stay idle 15 minutes) and the token is gone.

Create one at **Settings → Developer settings → Fine-grained tokens**
(<https://github.com/settings/personal-access-tokens/new>):

| Setting | Value |
|---|---|
| Resource owner | `egovernments` |
| Repository access | Only select repositories → **DIGIT-Studio** |
| Repository permissions | **Contents: Read** and **Actions: Read and write** |
| Expiration | short (7–30 days) |

Nothing else is needed. The token cannot read code, secrets, or any other repo.

> If the org requires approval for fine-grained tokens, an owner approves it once.

## What it does

1. **Read** — branches, then the selected branch's `build/build-config.yml`.
2. **Cascade** — the config is parsed into module → service → image-name; each
   dropdown filters the next. New services on a feature branch appear automatically.
3. **Dispatch** — the Run button posts `workflow_dispatch` to `code-build.yaml` with
   `ref` + `service`. Needs `Actions: write`.
4. **Watch** — the page polls the run and links to it.

The build itself runs the central engine in
`egovernments/DIGIT-DevOps/.github/workflows/reusable-build.yml`.

## Two front doors

- **This page** — cascading, branch-driven, needs a scoped token.
- **GitHub-native** — `Actions → Code Build → Run workflow` uses your session, no token,
  but choices are static.

Both target the same `code-build.yaml`.
