# Build workflow

`reusable-build.yaml` builds and pushes a service image, gated by Trivy.

## Pipeline

```
resolve-config ─▶ code-scan ─▶ build  ──────────────────────────────────┐
                  (Trivy fs)   │ 1. build image(s) locally (app + db, amd64)
                               │ 2. image-scan the built image(s) (Trivy)
                               │ 3. push multi-arch (app + db) + cosign sign
                  └─ default branch only ─┘ (CRITICAL at either stage blocks push)
```

The flow is **code scan → build → scan the built image → push**, so the image
that is scanned is exactly the one that gets pushed (no throwaway build), and a
CRITICAL at either stage blocks the push.

1. **resolve-config** — reads `build/build-config.yml`, resolves the app work-dir /
   Dockerfile for `service` and any `<service>-db` entry, computes the tag
   `<branch>-<short-sha>`, and decides the **scan policy** (`is_default`).
2. **code-scan** — Trivy filesystem scan of the work-dir. A **CRITICAL** fails the
   job, so the build never starts.
3. **build** (one job, ordered steps):
   - builds the app image — and the `<service>-db` image when present — **locally**
     (amd64) so the exact artifact can be scanned;
   - **image-scans** both with Trivy; the app and db findings are combined into one
     report under the same service, and a **CRITICAL** in either fails the job
     before any push;
   - **pushes** multi-arch (app + db) with GitHub Actions layer cache (the pushed
     amd64 is the scanned layers), then signs the pushed digest(s) with **cosign
     keyless** (GitHub OIDC → Fulcio → Rekor; no private key). Signing is skipped
     when `push: false` or `enable_cosign: false`.

   Build → scan → push run in one job because a locally-built image can't cross
   GitHub job boundaries without a heavy tarball transfer.

## Scan policy

The Trivy gate runs **only when the build ref is the repo's default branch**
(`build_branch`, or the triggering ref when empty). On any other branch the scans
are **skipped** and the image is built + pushed directly — so feature-branch builds
are fast and never blocked, while `master` is gated (a CRITICAL blocks the push).
Set `enable_trivy: false` to disable scanning entirely.

The image scan publishes to the caller's `gh-pages/security/trivy` via
`.trivy/dashboard/publish.sh` (app + db findings under one service), regardless of
the gate result.

## Inputs

| Input | Default | Purpose |
|---|---|---|
| `service` | — (required) | Image name; must match an `image-name` in the config |
| `build_branch` | `""` | Branch/ref whose code is checked out and built; empty = the ref that triggered the run |
| `service_folder` | `""` | WORK_DIR fallback when the config has no entry |
| `config_path` | `build/build-config.yml` | Build config location |
| `registry_namespace` | `egovio` | Image namespace |
| `platforms` | `linux/amd64,linux/arm64` | buildx platforms |
| `default_dockerfile` | `build/maven/Dockerfile` | Dockerfile when the entry sets none |
| `runs_on` | `ubuntu-latest` | Runner label |
| `push` | `true` | `false` = build-only validation |
| `enable_trivy` | `true` | Run the Trivy gate on the **default branch only**; other branches build unscanned |
| `enable_cosign` | `true` | Sign pushed images with cosign keyless; needs `id-token: write` from the caller |

Secrets: `DOCKER_USERNAME`, `DOCKER_ACCESS_TOKEN`.

The caller job must grant `id-token: write` (for cosign keyless) and
`contents: write` (for the Trivy gh-pages publish):

```yaml
jobs:
  build:
    permissions:
      contents: write
      id-token: write
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-build.yaml@reusable-build-v1
    ...
```

## Verifying a signature

```bash
cosign verify egovio/<service>:<tag> \
  --certificate-identity-regexp 'https://github.com/<org>/<repo>/.github/workflows/' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```
Outputs: `docker_image`, `db_image`.

## Disabling scans

Set `enable_trivy: false` to skip both gates (e.g. a repo without the Trivy
toolkit). The build then runs straight after resolve.

## Trivy toolkit

Mirrors health-campaign-services: `aquasecurity/trivy-action`, offline scan,
`CRITICAL,HIGH,MEDIUM` reported, CRITICAL blocks. The dashboard is published to
`https://<owner>.github.io/<repo>/security/trivy/`.
