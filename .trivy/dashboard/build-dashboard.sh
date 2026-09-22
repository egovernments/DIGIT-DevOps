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

# Count fresh reports (works whether they sit at the results root or in a subdir,
# e.g. an artifact that kept a json/ prefix) and what is already on record.
fresh=$(find "$SRC" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
existing=$(ls "$SITE/data/$DOMAIN"/*.json 2>/dev/null | wc -l | tr -d ' ')
min="${MIN_REPORTS:-0}"

# Guard against a failed / incomplete run destroying the last good dashboard: only
# replace this domain's data when the fresh set is non-empty AND (no minimum was
# given, or it clears the minimum, or it is at least as large as what we already
# have). The other domain's data stays untouched either way.
if [ "$fresh" -eq 0 ] || { [ "$min" -gt 0 ] && [ "$fresh" -lt "$min" ] && [ "$fresh" -lt "$existing" ]; }; then
  echo "::warning title=Dashboard::$DOMAIN: only $fresh fresh report(s) (expected >= $min, $existing already on record); keeping existing data instead of overwriting."
else
  rm -f "$SITE/data/$DOMAIN"/*.json 2>/dev/null || true
  find "$SRC" -type f -name '*.json' -exec cp {} "$SITE/data/$DOMAIN/" \; 2>/dev/null || true
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
