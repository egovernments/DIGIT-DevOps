#!/usr/bin/env bash
# Stage a domain's Trivy JSON into the gh-pages tree and (re)build the dashboard
# from BOTH domains that are present, so the image and Helm scans (separate
# workflows) each refresh their half of one combined dashboard.
#
# The site is published under security/trivy/ so it serves at
#   https://<org>.github.io/<repo>/security/trivy/
#
# Args: <domain: images|helm> <results-json-dir> <pages-dir> [repo-url] [ref]
set -euo pipefail
DOMAIN="$1"; SRC="$2"; PAGES="$3"; REPO_URL="${4:-}"; REF="${5:-}"
here="$(cd "$(dirname "$0")" && pwd)"
SITE="$PAGES/security/trivy"          # served at /security/trivy/

mkdir -p "$SITE/data/images" "$SITE/data/helm"
# replace only this domain's data; the other domain's stays as-is on gh-pages
rm -f "$SITE/data/$DOMAIN"/*.json 2>/dev/null || true
if ls "$SRC"/*.json >/dev/null 2>&1; then
  cp "$SRC"/*.json "$SITE/data/$DOMAIN/"
fi
echo "images json: $(ls "$SITE/data/images"/*.json 2>/dev/null | wc -l | tr -d ' ')  helm json: $(ls "$SITE/data/helm"/*.json 2>/dev/null | wc -l | tr -d ' ')"

# Only Helm findings carry source-file links, so those links must use the branch
# the Helm scan ran on. Persist it with the Helm data so an image-only rebuild
# doesn't rewrite the links to whatever ref it was passed.
if [ "$DOMAIN" = "helm" ] && [ -n "$REF" ]; then echo "$REF" > "$SITE/data/helm/.ref"; fi
eff_ref="$REF"
[ -s "$SITE/data/helm/.ref" ] && eff_ref="$(cat "$SITE/data/helm/.ref")"

args=(--images "$SITE/data/images" --helm "$SITE/data/helm" --out "$SITE"
      --title "DIGIT · Container & Chart Security")
if [ -n "$REPO_URL" ] && [ -n "$eff_ref" ]; then
  args+=(--repo-url "$REPO_URL" --ref "$eff_ref")
fi
python3 "$here/generate.py" "${args[@]}"

# .nojekyll at the site root keeps GitHub Pages from mangling the static output
touch "$PAGES/.nojekyll"
