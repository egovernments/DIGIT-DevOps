# Build workflow

`reusable-build.yaml` builds and pushes a service image, gated by Trivy.

## Pipeline

```
resolve-config ─▶ code-scan ─▶ image-scan ─▶ build (push)
                  (Trivy fs)    (Trivy image)   app + db, multi-arch
```

1. **resolve-config** — reads `build/build-config.yml`, resolves the app work-dir /
   Dockerfile for `service` and any `<service>-db` entry, computes the tag
   `<branch>-<short-sha>`.
2. **code-scan** — Trivy filesystem scan of the work-dir. A **CRITICAL** finding
   fails the job and the build is skipped.
3. **image-scan** — builds the image locally (amd64) and Trivy-scans it. A
   **CRITICAL** finding fails the job, so the image is never pushed.
4. **build** — multi-arch buildx push of the app image (and `<service>-db` when
   present), with GitHub Actions layer cache.

Every scan publishes to the caller's `gh-pages/security/trivy` via
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
| `enable_trivy` | `true` | Run scans; needs `.trivy/dashboard` in the caller |

Secrets: `DOCKER_USERNAME`, `DOCKER_ACCESS_TOKEN`.
Outputs: `docker_image`, `db_image`.

## Disabling scans

Set `enable_trivy: false` to skip both gates (e.g. a repo without the Trivy
toolkit). The build then runs straight after resolve.

## Trivy toolkit

Mirrors health-campaign-services: `aquasecurity/trivy-action`, offline scan,
`CRITICAL,HIGH,MEDIUM` reported, CRITICAL blocks. The dashboard is published to
`https://<owner>.github.io/<repo>/security/trivy/`.
