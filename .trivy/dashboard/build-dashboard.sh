#!/usr/bin/env bash
# Stage a scan's Trivy JSON into the gh-pages tree and (re)build its dashboard.
#
# There are two separate dashboards under one site:
#   security/trivy/docker/  - container-image vulnerabilities  (image scan)
#   security/trivy/helm/    - Helm-chart misconfigurations      (helm scan)
# plus a landing security/trivy/ that links to both. Each scan refreshes only
# its own dashboard; the landing page is rebuilt from both domains' summaries.
#
# Args:  <domain: images|helm>  <results-json-dir>  <pages-dir>  [repo-url]  [ref]
# Env :  MIN_REPORTS  ACTOR  SCANNED_AT
set -euo pipefail
DOMAIN_IN="$1"; SRC="$2"; PAGES="$3"; REPO_URL="${4:-}"; REF="${5:-}"
here="$(cd "$(dirname "$0")" && pwd)"
SITE="$PAGES/security/trivy"                 # served at /security/trivy/

# workflow calls this "images"; the dashboard/URL is "docker"
case "$DOMAIN_IN" in
  images|docker) DOMAIN="docker"; RAW="$SITE/data/images" ;;
  helm)          DOMAIN="helm";   RAW="$SITE/data/helm" ;;
  *) echo "unknown domain '$DOMAIN_IN'"; exit 1 ;;
esac
mkdir -p "$RAW"

# publish the shared logo (favicon + brand) at the site root
cp "$here/logo.svg" "$SITE/logo.svg" 2>/dev/null || true

# Count fresh reports (works whether they sit at the results root or in a subdir,
# e.g. an artifact that kept a json/ prefix) and what is already on record.
fresh=$(find "$SRC" -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
existing=$(find "$RAW" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')
min="${MIN_REPORTS:-0}"

# Guard against a failed / incomplete run destroying the last good dashboard: only
# replace this domain's raw data when the fresh set is non-empty AND (no minimum
# was given, or it clears the minimum, or it is at least as large as what we have).
if [ "$fresh" -eq 0 ] || { [ "$min" -gt 0 ] && [ "$fresh" -lt "$min" ] && [ "$fresh" -lt "$existing" ]; }; then
  echo "::warning title=Dashboard::$DOMAIN: only $fresh fresh report(s) (expected >= $min, $existing already on record); keeping existing data instead of overwriting."
else
  rm -f "$RAW"/*.json 2>/dev/null || true
  find "$SRC" -type f -name '*.json' -exec cp {} "$RAW/" \; 2>/dev/null || true
fi
echo "$DOMAIN raw json: $(find "$RAW" -maxdepth 1 -type f -name '*.json' 2>/dev/null | wc -l | tr -d ' ')"

args=(domain --domain "$DOMAIN" --data "$RAW" --site "$SITE")
[ -n "$REF" ]        && args+=(--branch "$REF" --ref "$REF")
[ -n "$REPO_URL" ]   && args+=(--repo-url "$REPO_URL")
[ -n "${ACTOR:-}" ]  && args+=(--actor "$ACTOR")
[ -n "${SCANNED_AT:-}" ] && args+=(--scanned-at "$SCANNED_AT")
python3 "$here/generate.py" "${args[@]}"

# rebuild the landing page from whichever domains have been scanned so far
python3 "$here/generate.py" landing --site "$SITE"

# .nojekyll at the site root keeps GitHub Pages from mangling the static output
touch "$PAGES/.nojekyll"
