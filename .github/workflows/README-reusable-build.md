# Reusable Build workflow

Central Docker build engine shared by eGov service repositories. Callers keep a
thin workflow that only defines their service menu and delegate the build to this
one. Upgrades made here (action versions, yq, buildx, cache, security gates) are
inherited by every caller on its next run.

- Engine: `.github/workflows/reusable-build.yaml` (`on: workflow_call`)
- Pin tag for callers: `@reusable-build-v1` (moving major), or `@reusable-build-v1.x.y` (immutable)

## What it does

1. Checks out the caller repo.
2. Reads the caller's build config (`build/build-config.yml` by default) and
   resolves the app work-dir / Dockerfile for `service`, and the optional
   `<service>-db` entry.
3. Computes the tag `<branch>-<short-sha>`.
4. Builds and pushes `namespace/<service>` (and `namespace/<service>-db` when a
   db entry exists) multi-arch, with GitHub Actions layer cache.

## Inputs

| Input | Required | Default | Purpose |
|-------|----------|---------|---------|
| `service` | yes | - | Image name to build; must match an `image-name` in the config |
| `service_folder` | no | `""` | WORK_DIR fallback (`<folder>/<service>`) when the config has no entry |
| `config_path` | no | `build/build-config.yml` | Build config location |
| `registry_namespace` | no | `egovio` | Image namespace |
| `platforms` | no | `linux/amd64,linux/arm64` | buildx target platforms |
| `default_dockerfile` | no | `build/maven/Dockerfile` | Dockerfile when the config entry sets none |
| `runs_on` | no | `ubuntu-latest` | Runner label |
| `push` | no | `true` | Set `false` for build-only validation (no registry push) |

Secrets (required): `DOCKER_USERNAME`, `DOCKER_ACCESS_TOKEN`.
Outputs: `docker_image`, `db_image`.

## Caller example

```yaml
jobs:
  build:
    uses: egovernments/DIGIT-DevOps/.github/workflows/reusable-build.yaml@reusable-build-v1
    with:
      service: ${{ inputs.service }}
      service_folder: ${{ inputs.service_folder }}
    secrets:
      DOCKER_USERNAME: ${{ vars.DOCKER_USERNAME }}
      DOCKER_ACCESS_TOKEN: ${{ secrets.DOCKER_ACCESS_TOKEN }}
```

## Upgrade procedure (maintainers)

1. Change `reusable-build.yaml` on a feature branch, open a PR, merge to `master`.
2. Move the major tag to the merge commit and cut an immutable patch tag:
   ```sh
   git tag -f reusable-build-v1 <sha>
   git tag  reusable-build-v1.<minor>.<patch> <sha>
   git push -f origin reusable-build-v1
   git push origin reusable-build-v1.<minor>.<patch>
   ```
3. Breaking change: cut `reusable-build-v2` and let callers opt in.

Callers pinned to `@reusable-build-v1` pick up compatible upgrades automatically.
