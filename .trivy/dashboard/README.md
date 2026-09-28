# Security dashboard

Trivy scan results published to **GitHub Pages** (`gh-pages` branch) under
`security/trivy/` as two separate, shareable dashboards plus a landing page:

    https://<org>.github.io/<repo>/security/trivy/          landing (both domains)
    https://<org>.github.io/<repo>/security/trivy/docker/   container images
    https://<org>.github.io/<repo>/security/trivy/helm/     Helm charts

Both dashboards render scan timestamps in the **viewer's local timezone** and
carry a run picker (recent runs). The Helm dashboard adds a **branch picker**
(searchable), since the Helm scan can run per branch.

## Pieces
- `generate.py` — aggregates Trivy JSON per domain, archives each run under
  `<domain>/data/runs/` (a per-run model + `manifest.json`), and renders:
  - `domain --domain <docker|helm> --data <raw-json-dir> --site <site>` → one
    dashboard page (a light bootstrap of run metadata; the heavy per-run model is
    fetched from `data/runs/<id>.json` on load and on run switch).
  - `landing --site <site>` → the landing page, from each domain's `summary.json`.
- `dash.html` — the single-domain dashboard UI (overview with score ring + charts,
  asset table with drill-down, findings table). Parametrised by the embedded domain.
- `landing.html` — the landing page (posture + a card per domain).
- `logo.svg` — brand logo (favicon + header), copied to the site root.
- `build-dashboard.sh` — stages one scan's JSON, builds that domain's dashboard,
  then rebuilds the landing page from both domains' summaries.

## How CI uses it
Each scan workflow ends with a `dashboard` job that:
1. downloads its scan's JSON,
2. checks out the existing `gh-pages` (to keep the other domain's data + summary),
3. runs `build-dashboard.sh <images|helm> <json-dir> pages <repo-url> <ref>`
   (with `ACTOR` / optional `SCANNED_AT` in the environment for the run label),
4. publishes `pages/` to `gh-pages` (peaceiris/actions-gh-pages).

The image workflow refreshes `docker/`, the Helm workflow refreshes `helm/`; each
also rebuilds the shared landing page. `MIN_REPORTS` guards against an incomplete
run overwriting a good report set.

**Prerequisite:** enable GitHub Pages for this repo with source = `gh-pages` branch.
The repo is public, so the site (and the findings on it) is public — decide whether
that audience is acceptable before enabling.

## Run locally
```bash
SITE=site/security/trivy; mkdir -p "$SITE/data/images" "$SITE/data/helm"
cp <image-json>/*.json "$SITE/data/images/"; cp <helm-json>/*.json "$SITE/data/helm/"
cp .trivy/dashboard/logo.svg "$SITE/logo.svg"
python3 .trivy/dashboard/generate.py domain --domain docker --data "$SITE/data/images" \
  --site "$SITE" --repo-url https://github.com/egovernments/DIGIT-DevOps --ref master --actor you
python3 .trivy/dashboard/generate.py domain --domain helm --data "$SITE/data/helm" \
  --site "$SITE" --repo-url https://github.com/egovernments/DIGIT-DevOps --ref master --actor you
python3 .trivy/dashboard/generate.py landing --site "$SITE"
# the pages fetch run JSON, so serve over HTTP (not file://):
( cd site && python3 -m http.server 8000 )   # → http://localhost:8000/security/trivy/
```
Deep-links: `?view=assets`, `?view=findings`, `?theme=dark`.
