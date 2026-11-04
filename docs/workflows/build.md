# Build workflow

`reusable-build.yaml` builds and pushes a service image, gated by Trivy.

## Pipeline

```
resolve-config ─▶ code-scan ─▶ image-scan ─▶ build (push + sign)
                  (Trivy fs)    (Trivy image)   app + db, multi-arch, cosign
                  └── default branch only ──┘
```

1. **resolve-config** — reads `build/build-config.yml`, resolves the app work-dir /
   Dockerfile for `service` and any `<service>-db` entry, computes the tag
   `<branch>-<short-sha>`, and decides the **scan policy** (`is_default`).
2. **code-scan** — Trivy filesystem scan of the work-dir. A **CRITICAL** finding
   fails the job and the build is skipped.
3. **image-scan** — builds the image locally (amd64) and Trivy-scans it. A
   **CRITICAL** finding fails the job, so the image is never pushed.
4. **build** — multi-arch buildx push of the app image (and `<service>-db` when
   present), with GitHub Actions layer cache. The pushed image digest(s) are then
   signed with **cosign keyless** (GitHub OIDC → Fulcio certificate → Rekor
   transparency log — no private key to manage). Signing is skipped when
   `push: false` or `enable_cosign: false`.

## Scan policy

The Trivy gate runs **only when the build ref is the repo's default branch**
(`build_branch`, or the triggering ref when empty). On any other branch, both
scan jobs are **skipped** and the build runs normally — so feature-branch builds
are fast and never blocked, while `master` is gated (a CRITICAL blocks the push).
Set `enable_trivy: false` to disable scanning entirely.

Each scan publishes to the caller's `gh-pages/security/trivy` via
`.trivy/dashboard/publish.sh`, regardless of the gate result.

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
