# Code Build dispatcher (`/actions`)

A self-contained page that triggers the **Code Build** workflow for any service in
`build/build-config.yml`, with a live **branch → service** selection read from the
chosen branch.

It is a single static file (`index.html`). It works three ways, with no server:

- opened locally (`file://`),
- served from GitHub Pages, or
- any static host.

All GitHub calls go straight to `api.github.com` from your browser.

## Authentication

The page uses a **fine-grained personal access token**, kept for **this browser tab
only** (session storage) — it survives a refresh so you aren't re-prompted, is cleared
when you close the tab or stay idle 15 minutes, is never shared with other tabs or
devices, and a strict Content-Security-Policy means it can only ever reach
`api.github.com`.

Create one at **Settings → Developer settings → Fine-grained tokens**
(<https://github.com/settings/personal-access-tokens/new>):

| Setting | Value |
|---|---|
| Resource owner | your org |
| Repository access | Only select repositories → the consumer repo |
| Repository permissions | **Contents: Read** and **Actions: Read and write** |
| Expiration | short (7–30 days) |

Nothing else is needed. The token cannot read code, secrets, or any other repo.

> If the org requires approval for fine-grained tokens, an owner approves it once.

## What it does

1. **Read** — branches, then the selected branch's `build/build-config.yml`.
2. **Pick** — choose a branch, then a service (image-name) from that branch's config.
3. **Dispatch** — the Run button posts `workflow_dispatch` to `code-build.yaml` on the
   default branch with `build_branch` + `service`. Needs `Actions: write`.
4. **Watch** — the page polls the run and links to it.

The build itself runs the central engine in
`egovernments/DIGIT-DevOps/.github/workflows/reusable-build.yaml`.

## Two front doors

- **This page** — live, searchable branch picker, needs a scoped token.
- **GitHub-native** — `Actions → Code Build → Run workflow` uses your session, no token;
  the branch + service choices are synced dropdowns.

Both target the same `code-build.yaml`.
