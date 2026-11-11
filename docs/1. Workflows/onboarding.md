# Onboarding a repo to Code Build

A step-by-step runbook to put a service repository on the central build CI. When you
finish, the repo builds, scans and signs its images from a branch/service picker — no
per-build YAML to hand-write — with a security dashboard on GitHub Pages.

> New to the system? Skim the [overview](README.md) first for how the pieces fit.

## What you'll end up with

- **Build — Code / Build — Setup** workflows in the repo.
- A **landing page**, an **`/actions`** build dispatcher, and a **Trivy dashboard** on
  GitHub Pages.
- Images **built → image-scanned (CRITICAL blocks the push) → pushed → cosign-signed**,
  for the app image and its optional `-db` image.

---

## Prerequisites (one-time, org level)

These exist once for the whole org — skip if already set up.

1. **The build GitHub App** — permissions Contents + Workflows + Pages (write) and
   Metadata (read), installed on the consumer repos, and on the default-branch ruleset
   **bypass** list. Create it once per [setup.md](setup.md). You'll need its **Client ID**
   and a **private key** for each repo's secrets.
2. **(Only if you want `oauth` sign-in)** the OAuth App + broker Worker — see
   [oauth-worker.md](oauth-worker.md). Not needed for the default `pat` sign-in.

---

## Per-repo steps

### 1. Add `build/build-config.yml`

List the services to build. **Sample (placeholders — use your own paths/names):**

```yaml
config:
  # name: builds/<repo>/<module>/<service-key>
  #   the <module>/<service-key> part groups the service in the Code Build dropdowns.
  - name: "builds/my-repo/billing/collection-service"
    build:
      - work-dir: "municipal-services/collection-service"    # Docker build context
        image-name: "collection-service"                     # -> <namespace>/collection-service
        dockerfile: "build/maven/Dockerfile"                 # optional; omit to use the engine default
      - work-dir: "municipal-services/collection-service/src/main/resources/db"
        image-name: "collection-service-db"                  # optional DB image (built, scanned & pushed too)

  - name: "builds/my-repo/billing/billing-service"
    build:
      - work-dir: "municipal-services/billing-service"
        image-name: "billing-service"
```

Rules:
- An entry whose `image-name` ends in **`-db`** is treated as that service's database image.
- `dockerfile` is **optional** (engine default: `build/maven/Dockerfile`).
- The 3rd/4th segments of `name` (`<module>/<service-key>`) drive the dropdown grouping.

### 2. Install the App + add secrets

1. **Install** the build GitHub App on this repo.
2. **Ruleset bypass** — add the App to the default branch's ruleset bypass list
   (Settings → Rules → Rulesets → the active ruleset → *Bypass list* → add the App →
   **Always**), so Setup can push directly to the default branch.
3. **Secrets & variables** (Settings → Secrets and variables → Actions):

   | Name | Kind | Value |
   |---|---|---|
   | `BUILD_APP_CLIENT_ID` | secret | the App's Client ID (`Iv…`) |
   | `BUILD_APP_PRIVATE_KEY` | secret | the App's private key (PEM) |
   | `DOCKER_USERNAME` | **variable** | registry username |
   | `DOCKER_ACCESS_TOKEN` | secret | registry access token |
   | `TRIVY_SCAN_BRANCHES` | **variable** *(optional)* | branches to Trivy-scan + gate, one per line (e.g. `master`, `develop`); unset = default branch only |

### 3. Add the Setup caller

Commit `.github/workflows/setup.yaml`:

```yaml
name: Build — Setup
on:
  workflow_dispatch:
    inputs:
      mode:                      # full = provision/upgrade; sync = only refresh dropdowns
        type: choice
        options: [full, sync]
        default: full
      sync_branch:               # sync mode: pull a branch's new services into the dropdown
        type: choice
        default: master
        options: [master]
      auth_mode:                 # full mode: /actions sign-in method
        type: choice
        options: [PAT, OAuth]    # PAT = paste a token (default); OAuth = Sign in with GitHub
        default: PAT
jobs:
  setup:
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-setup.yaml@reusable-build-v1
    with:
      mode: ${{ inputs.mode }}
      sync_branch: ${{ inputs.sync_branch }}
      auth_mode: ${{ inputs.auth_mode }}
    secrets:
      APP_CLIENT_ID: ${{ secrets.BUILD_APP_CLIENT_ID }}
      APP_PRIVATE_KEY: ${{ secrets.BUILD_APP_PRIVATE_KEY }}
```

### 4. Run **Build — Setup** (mode: full)

Actions → **Build — Setup** → **Run workflow** (keep *Use workflow from* on the default
branch — Setup refuses any other; leave `mode: full`, pick `auth_mode`). It direct-pushes
to the default branch and publishes Pages:

- `code-build.yaml` (**Build — Code**) with the service + branch dropdowns populated,
- `.trivy/dashboard/` toolkit,
- gh-pages: landing page `/`, `/actions` dispatcher, `/security/trivy`.

> The first run adds the `mode`/`auth_mode` choices to this repo's own `setup.yaml`, so
> picking **`sync`** or **`OAuth`** is available from the **second** run onward.

### 5. Enable Pages (if not automatic)

Setup tries to enable Pages for you. If it couldn't, set Settings → Pages → Branch
**`gh-pages`**, folder **`/`**.

### 6. Verify

- Open `https://<owner>.github.io/<repo>/` — the landing page.
- **Run a build**: Actions → **Build — Code** → Run (branch + service dropdowns, or tick
  **All services**), or use the **`/actions`** dispatcher.
- Watch the run. On a scanned branch (`TRIVY_SCAN_BRANCHES`, or the default branch) a
  **CRITICAL** blocks the push; the report lands at `/security/trivy/`.

---

## Day-2 operations

- **Add / remove a service** — edit `build/build-config.yml`, then run **Build — Setup**
  with **`mode: sync`** to refresh the dropdowns (service list is unioned, never dropped;
  branch list is refreshed). Use `sync_branch` to pull a feature branch's new services
  into the dropdown before it merges. (The `/actions` UI reads services live, so it needs
  no sync.)
- **Build everything** — run **Build — Code** with **All services** on (or the checkbox in
  the `/actions` UI) to build every service in `build-config.yml` from the chosen branch.
- **Change which branches are scanned** — edit the `TRIVY_SCAN_BRANCHES` variable.
- **Switch the sign-in method** — re-run **Build — Setup** (`mode: full`) with a different `auth_mode`.
- **Engine upgrades are automatic** — callers pin `@reusable-build-v1`, which moves when
  the engine changes in DIGIT-DevOps. Nothing to do per repo.

## How a build runs (recap)

`code-scan (gate)` → `build image (app + db)` → `image-scan the built image (app + db)`
→ `push multi-arch` → `cosign sign`. Scans gate the **default branch** only; feature
branches build + push unscanned. Full detail: [build.md](build.md).
