# Code Build: onboarding a service

Two cases:

- **A new service in a repo that is already on Code Build** - just edit the build
  config (step A below), then resync the dropdowns.
- **A repo that is not yet on Code Build** - do the one-time repo onboarding,
  which is covered in full in [../workflows/onboarding.md](<../1. Workflows/onboarding.md>).
  The essentials are summarized at the end of this page.

## A. Add a new service to the build config

The service list lives in `build/build-config.yml` in the service repo. Add an
entry whose `image-name` is the image you want in the registry.

```yaml
config:
  # name: builds/<repo>/<module>/<service-key>
  #   the <module>/<service-key> part groups the service in the Code Build dropdowns.
  - name: "builds/my-repo/billing/collection-service"
    build:
      - work-dir: "municipal-services/collection-service"   # Docker build context
        image-name: "collection-service"                    # -> egovio/collection-service
        dockerfile: "build/maven/Dockerfile"                # optional; omit to use the engine default
      - work-dir: "municipal-services/collection-service/src/main/resources/db"
        image-name: "collection-service-db"                 # optional migration image -> egovio/collection-service-db
```

Rules:

- **`image-name`** is the registry image name. `egovio/<image-name>` is where it
  lands (namespace default `egovio`, overridable with `registry_namespace`).
- An entry whose `image-name` ends in **`-db`** is treated as that service's
  **database / migration image**. The engine builds, scans and pushes it in the
  same run, paired with the app image. Leave it out if the service has no
  migrations.
- **`work-dir`** is the Docker build context (passed to the Dockerfile as the
  `WORK_DIR` build arg).
- **`dockerfile`** is optional; the engine default is `build/maven/Dockerfile`.
- The 3rd and 4th segments of `name` (`<module>/<service-key>`) drive how the
  service is grouped in the "Build - Code" dropdowns.

After editing, run **Build - Setup** with `mode: sync` to refresh the service
dropdown. The service list is unioned (never dropped), and you can point
`sync_branch` at a feature branch to surface its new services before it merges.
The `/actions` dispatcher reads the list live, so it needs no resync.

## Dockerfile expectations

- The build context is `work-dir`, exposed as the `WORK_DIR` build arg; the
  default `build/maven/Dockerfile` consumes it. If you supply your own
  Dockerfile, keep it buildable for **both** `linux/amd64` and `linux/arm64`,
  because the push step is multi-arch.
- Do **not** run unit or integration tests inside the image build. Tests belong
  in a separate CI job; running them at image-build time makes every build slow
  and flaky and couples the gate to test infra. See the note in
  [maintenance.md](maintenance.md#common-build-failures).
- Keep the image minimal; the Trivy image scan reports CRITICAL/HIGH/MEDIUM and
  a CRITICAL blocks the push.

## Image naming recap

| Config `image-name` | Pushed image |
|---|---|
| `collection-service` | `docker.io/egovio/collection-service:<branch>-<sha>` |
| `collection-service-db` | `docker.io/egovio/collection-service-db:<branch>-<sha>` |

The downstream Helm chart and Kargo pipeline must reference these exact image
names. See [Helm Packaging & Releasing](<../3. Helm Packaging & Releasing/>)
and [Kargo Promotions](<../4. Kargo Promotions/>).

## Scan branches

Set which branches are scanned and gated through the `TRIVY_SCAN_BRANCHES` repo
variable (Settings -> Secrets and variables -> Actions -> Variables), one branch
per line, for example:

```
master
develop
```

The caller passes this as `scan_branches`. Unset = default branch only. No
workflow edit is needed to change it.

## B. One-time repo onboarding (summary)

Do this once per repo that has never used Code Build. Full runbook:
[../workflows/onboarding.md](<../1. Workflows/onboarding.md>).

1. **Install the build GitHub App** on the repo and add it to the default
   branch's ruleset **bypass** list (so setup can push directly).
2. **Add secrets / variables** (Settings -> Secrets and variables -> Actions):

   | Name | Kind | Value |
   |---|---|---|
   | `BUILD_APP_CLIENT_ID` | secret | the App Client ID (`Iv...`) |
   | `BUILD_APP_PRIVATE_KEY` | secret | the App private key (PEM) |
   | `DOCKER_USERNAME` | variable | registry username |
   | `DOCKER_ACCESS_TOKEN` | secret | registry access token |
   | `TRIVY_SCAN_BRANCHES` | variable (optional) | branches to scan + gate |

3. **Add `build/build-config.yml`** (section A above).
4. **Add the Setup caller** `.github/workflows/setup.yaml` calling
   `egovernments/DIGIT-DevOps/.github/workflows/reusable-setup.yaml@reusable-build-v1`.
5. **Run Build - Setup** (`mode: full`) from the default branch. It direct-pushes
   the `code-build.yaml` caller ("Build - Code") with populated dropdowns, the
   `.trivy/dashboard/` toolkit, and publishes the GitHub Pages landing page,
   `/actions` dispatcher, and `/security/trivy` dashboard.
6. **Enable Pages** (`gh-pages`, `/`) if setup could not do it automatically, and
   verify by running a build.
