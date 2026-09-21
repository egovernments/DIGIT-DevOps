#!/usr/bin/env bash
# Stage a domain's Trivy JSON into the gh-pages data tree and (re)build index.html
# from BOTH domains that are present, so the image and Helm scans (separate
# workflows) each refresh their half of one combined dashboard.
#
# Args: <domain: images|helm> <results-json-dir> <pages-dir> [repo-url] [ref]
set -euo pipefail
DOMAIN="$1"; SRC="$2"; PAGES="$3"; REPO_URL="${4:-}"; REF="${5:-}"
here="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$PAGES/data/images" "$PAGES/data/helm"
# replace only this domain's data; the other domain's stays as-is on gh-pages
rm -f "$PAGES/data/$DOMAIN"/*.json 2>/dev/null || true
if ls "$SRC"/*.json >/dev/null 2>&1; then
  cp "$SRC"/*.json "$PAGES/data/$DOMAIN/"
fi
echo "images json: $(ls "$PAGES/data/images"/*.json 2>/dev/null | wc -l | tr -d ' ')  helm json: $(ls "$PAGES/data/helm"/*.json 2>/dev/null | wc -l | tr -d ' ')"

args=(--images "$PAGES/data/images" --helm "$PAGES/data/helm" --out "$PAGES"
      --title "DIGIT · Container & Chart Security")
if [ -n "$REPO_URL" ] && [ -n "$REF" ]; then
  args+=(--repo-url "$REPO_URL" --ref "$REF")
fi
python3 "$here/generate.py" "${args[@]}"
# a .nojekyll file keeps GitHub Pages from mangling the static site
touch "$PAGES/.nojekyll"
