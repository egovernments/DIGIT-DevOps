# Security dashboard

A single self-contained `index.html` (no build step, no external assets) that
aggregates Trivy JSON from the image and Helm scans into one console, published
to **GitHub Pages** (`gh-pages` branch) under `security/trivy/`, i.e.

    https://<org>.github.io/<repo>/security/trivy/

## Pieces
- `generate.py` — aggregates Trivy JSON → `index.html`. Groups image reports by
  repo (each repo's tags newest→oldest), builds fleet aggregates from each repo's
  latest tag, and emits per-tag drill-downs.
- `template.html` — the UI (repo → tags → per-tag CVEs, misconfig view, overview).
- `build-dashboard.sh` — stages one domain's JSON into the `data/` tree and
  regenerates from **both** domains present, so the two scans each refresh their half.

## How CI uses it
Each scan workflow ends with a `dashboard` job that:
1. downloads its scan's JSON,
2. checks out the existing `gh-pages` (to keep the other domain's data),
3. runs `build-dashboard.sh <images|helm> <json-dir> pages <repo-url> <ref>`,
4. publishes `pages/` to `gh-pages` (peaceiris/actions-gh-pages).

The image workflow refreshes `data/images/`, the Helm workflow refreshes
`data/helm/`; both rebuild the combined `index.html`.

**Prerequisite:** enable GitHub Pages for this repo with source = `gh-pages` branch.
The repo is public, so the site (and the findings on it) is public — decide whether
that audience is acceptable before enabling.

## Run locally
```bash
python3 .trivy/dashboard/generate.py \
  --images <dir-of-image-json> --helm <dir-of-helm-json> --out site \
  --repo-url https://github.com/egovernments/DIGIT-DevOps --ref master
open site/index.html
```
Deep-links: `?view=images&repo=<repo>&tag=<tag>`, `?view=rules`, `?theme=dark`.
