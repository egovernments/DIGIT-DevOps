# Reusable build workflows

Central CI for eGov service repositories. A consumer repo keeps one thin caller and a
build config; the engine, the dispatcher UI, the security scanning and the dashboards
are all provisioned from here and upgraded centrally.

**→ Onboarding a new repo? Start with the [onboarding runbook](onboarding.md).**

## How it fits together

```
DIGIT-DevOps (this repo)                      Consumer repo (e.g. a service repo)
  reusable-*.yaml ──── pinned @reusable-build-v1 ───▶ code-build.yaml   (thin caller)
  templates/consumer/ ─────── run Setup once ───────▶ sync-code-build.yaml, .trivy/
  promote-reusable-tag.yaml                            gh-pages: /  /actions  /security/trivy
    └ auto-moves the tag on every merge here
```

- **Engine** lives here; consumers call it by tag, so a change merged here ships to all of them.
- **Setup** (run once per repo, authenticates as a GitHub App) scaffolds the caller, the sync workflow, the Trivy toolkit and the Pages.
- **Sync** keeps the Code Build dropdowns matching the repo's live branches and services.
- **Build** runs the engine: code-scan → build → image-scan → push → sign, gated on the default branch.

**Auth model:** Setup + Sync push straight to the default branch as a **GitHub App** (on
the ruleset bypass list); the **`/actions`** dispatcher signs a user in with a scoped,
per-tab **PAT** (default) or **Sign in with GitHub** (optional OAuth). No long-lived PAT
is stored anywhere.

## Documentation

| Doc | What it covers |
|---|---|
| **[onboarding.md](onboarding.md)** | **Start here** — step-by-step runbook to put a new repo on Code Build |
| [build.md](build.md) | The build engine (`reusable-build.yaml`): pipeline, scan policy, cosign, inputs |
| [setup.md](setup.md) | The Setup workflow + the GitHub App it needs, and the `auth_mode` toggle |
| [sync-code-build.md](sync-code-build.md) | How the service + branch dropdowns stay current |
| [actions-ui.md](actions-ui.md) | The landing page + `/actions` dispatcher, and sign-in methods |
| [oauth-worker.md](oauth-worker.md) | Optional "Sign in with GitHub" — the broker Worker (OAuth) |

### Components (this repo)

| Workflow | Role |
|---|---|
| `reusable-build.yaml` | The build engine (`on: workflow_call`) — [build.md](build.md) |
| `reusable-setup.yaml` | One-shot consumer scaffold — [setup.md](setup.md) |
| `reusable-code-build-sync.yaml` | Dropdown sync — [sync-code-build.md](sync-code-build.md) |
| `promote-reusable-tag.yaml` | Auto-moves `reusable-build-v1` on engine/template changes (runs here, not reusable) |

## Running a build (two doors)

- **GitHub-native** — Actions → **Build — Code** → Run workflow (session auth, synced service + branch dropdowns).
- **`/actions` UI** — `https://<owner>.github.io/<repo>/actions/`: a live branch → service picker. Signs in with a scoped PAT or Sign in with GitHub.

Both dispatch the same `code-build.yaml`.

## Versioning

Callers pin a moving major tag `@reusable-build-v1` (or an immutable `@reusable-build-v1.0.y`).

The move is **automated**: `promote-reusable-tag.yaml` runs when `reusable-*.yaml` or
`templates/consumer/**` change on master, repoints `reusable-build-v1` at the new master
tip, and cuts the next immutable `reusable-build-v1.0.<N>` snapshot — so merging a change
here rolls it out to every consumer with no manual tag move. Cut a new major tag
`reusable-build-v2` by hand for a breaking change.
