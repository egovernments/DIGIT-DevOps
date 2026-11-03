#!/usr/bin/env bash
# Publish one Trivy scan (code or image) for a service to the gh-pages
# dashboard under security/trivy/, then print the public report URL.
#
# Usage:
#   publish.sh <kind> <service> <build-id> <report.json> <gate>
#     kind     : code | image
#     service  : service / image name (becomes the URL slug)
#     build-id : unique run id (github.run_id)
#     report   : raw Trivy JSON for this scan
#     gate     : pass | fail  (fail = a blocking critical was found)
#
# Env (provided by the workflow):
#   GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_ACTOR, BRANCH, GITHUB_SERVER_URL
#
# The whole gh-pages tree is re-fetched and regenerated on each attempt, so
# concurrent pipeline runs for other services never clobber each other.
set -euo pipefail

KIND="$1"; SERVICE="$2"; BUILD="$3"; REPORT="$4"; GATE="${5:-pass}"
REPO_SLUG="${GITHUB_REPOSITORY}"
SERVER="${GITHUB_SERVER_URL:-https://github.com}"
REPO_URL="${SERVER}/${REPO_SLUG}"
RUN_URL="${REPO_URL}/actions/runs/${BUILD}"
DASH_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"

ok=false
for attempt in 1 2 3 4 5; do
  rm -rf "$WORK/ghpages"
  if git clone --quiet --depth 1 --branch gh-pages \
      "https://x-access-token:${GH_TOKEN}@github.com/${REPO_SLUG}.git" "$WORK/ghpages" 2>/dev/null; then
    :
  else
    # gh-pages doesn't exist yet - start an orphan branch
    mkdir -p "$WORK/ghpages"; ( cd "$WORK/ghpages"
      git init --quiet
      git remote add origin "https://x-access-token:${GH_TOKEN}@github.com/${REPO_SLUG}.git"
      git checkout --quiet --orphan gh-pages )
  fi

  SITE="$WORK/ghpages/security/trivy"
  # generator progress must go to stderr so stdout carries only the final URL
  python3 "$DASH_DIR/generate.py" scan \
    --service "$SERVICE" --kind "$KIND" --input "$REPORT" --site "$SITE" \
    --build-id "$BUILD" --commit "${GITHUB_SHA:-}" --branch "${BRANCH:-}" \
    --actor "${GITHUB_ACTOR:-}" --repo-url "$REPO_URL" --run-url "$RUN_URL" --gate "$GATE" >&2
  python3 "$DASH_DIR/generate.py" home --site "$SITE" >&2

  ( cd "$WORK/ghpages"
    touch .nojekyll
    git add -A
    git -c user.email="github-actions[bot]@users.noreply.github.com" \
        -c user.name="github-actions[bot]" \
        commit --quiet -m "trivy: ${KIND} scan for ${SERVICE} (build ${BUILD})" || exit 0
    git push --quiet origin gh-pages ) >&2 && { ok=true; break; }

  echo "gh-pages push attempt ${attempt} failed (likely a concurrent update); retrying..." >&2
  sleep $(( (RANDOM % 5) + 3 ))
done

rm -rf "$WORK"
$ok || { echo "::warning::could not publish the ${KIND} scan dashboard after 5 attempts"; }

URL="https://$(echo "$REPO_SLUG" | cut -d/ -f1).github.io/$(echo "$REPO_SLUG" | cut -d/ -f2)/security/trivy/${SERVICE}/?build=${BUILD}&kind=${KIND}"
echo "REPORT_URL=${URL}" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "$URL"
