# Trivy security dashboard

A static, per-service security dashboard published to the `gh-pages` branch
under `security/trivy/` and served at:

<https://egovernments.github.io/health-campaign-services/security/trivy/>

It is fed by the build pipeline (`.github/workflows/build.yaml`), which Trivy-
scans every service twice per build and gates the build on critical findings:

1. **Code scan** (`trivy fs`) over the service source - vulnerable
   dependencies and hard-coded secrets - **before** the image is built.
2. **Image scan** (`trivy image`) over the built image - OS and app packages -
   **before** it is pushed.

A critical finding at either stage aborts the build and the step prints the
report URL.

## Layout on gh-pages

```
security/trivy/
  index.html                          landing: one card per service + search
  logo.svg
  <service>/index.html                service dashboard (Code Scan + Image Scan)
  <service>/data/builds/<id>.json     full per-build model (code + image)
  <service>/data/builds/manifest.json last builds (the run dropdown)
  <service>/summary.json              latest build summary (home card)
```

A "build" is one pipeline run, keyed by the GitHub run id. Deep-link a specific
build with `?build=<run-id>` (and optionally `&kind=code|image`).

## Pieces

| File | Role |
|------|------|
| `generate.py` | aggregates a Trivy JSON into the model and renders the pages. `scan` ingests one code/image report for a build; `home` rebuilds the landing. |
| `home.html` | landing template (service cards, search). |
| `service.html` | service template (Code/Image nav, build dropdown, Excel export). |
| `publish.sh` | clones gh-pages, runs `generate.py`, pushes (concurrency-safe retry). |
| `logo.svg` | shield logo, copied to the site root by `generate.py`. |

## Enabling the published site

GitHub Pages must be set to serve from the **`gh-pages`** branch
(Settings → Pages → Branch: `gh-pages` / root). The pipeline creates the
branch on first publish; nothing else is required.
