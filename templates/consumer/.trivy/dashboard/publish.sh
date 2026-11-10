#!/usr/bin/env bash
# Publish one Trivy scan (code or image) for a service to the gh-pages
# dashboard under security/trivy/, then print the public report URL.
#
# Usage:
#   publish.sh <kind> <service> <build-id> <report.json> <gate>
#     kind     : code | image | home
#     service  : service / image name (becomes the URL slug)   [not used for home]
#     build-id : unique run id (github.run_id)                  [not used for home]
#     report   : raw Trivy JSON for this scan                   [not used for home]
#     gate     : pass | fail  (fail = a blocking critical was found)
#
#   kind=home just regenerates the dashboard landing (index) from every service's
#   summary and pushes — used once after a parallel all-services build.
#
# Env (provided by the workflow):
#   GH_TOKEN, GITHUB_REPOSITORY, GITHUB_SHA, GITHUB_ACTOR, BRANCH, GITHUB_SERVER_URL
#   PUBLISH_HOME  : 1 (default) also regenerates the landing index in this run;
#                   0 skips it (parallel all-services legs skip it, a final
#                   `home` run rebuilds the index once — no shared-file races).
#
# The whole gh-pages tree is re-fetched and regenerated on each attempt, so
# concurrent pipeline runs for other services never clobber each other.
set -euo pipefail

KIND="$1"; SERVICE="${2:-}"; BUILD="${3:-}"; REPORT="${4:-}"; GATE="${5:-pass}"
PUBLISH_HOME="${PUBLISH_HOME:-1}"
REPO_SLUG="${GITHUB_REPOSITORY}"
SERVER="${GITHUB_SERVER_URL:-https://github.com}"
REPO_URL="${SERVER}/${REPO_SLUG}"
RUN_URL="${REPO_URL}/actions/runs/${BUILD}"
DASH_DIR="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"

ok=false
for attempt in 1 2 3 4 5 6 7 8; do
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
  if [ "$KIND" != "home" ]; then
    python3 "$DASH_DIR/generate.py" scan \
      --service "$SERVICE" --kind "$KIND" --input "$REPORT" --site "$SITE" \
      --build-id "$BUILD" --commit "${GITHUB_SHA:-}" --branch "${BRANCH:-}" \
      --actor "${GITHUB_ACTOR:-}" --repo-url "$REPO_URL" --run-url "$RUN_URL" --gate "$GATE" >&2
  fi
  # Rebuild the landing index — always for a dedicated `home` run, otherwise only
  # when PUBLISH_HOME=1 (parallel all-services legs set it to 0 and let one final
  # `home` run own the shared index, so legs only touch their own disjoint subtree).
  if [ "$KIND" = "home" ] || [ "$PUBLISH_HOME" = "1" ]; then
    python3 "$DASH_DIR/generate.py" home --site "$SITE" >&2
  fi

  if [ "$KIND" = "home" ]; then MSG="trivy: refresh dashboard home"; else MSG="trivy: ${KIND} scan for ${SERVICE} (build ${BUILD})"; fi
  ( cd "$WORK/ghpages"
    touch .nojekyll
    git add -A
    git -c user.email="github-actions[bot]@users.noreply.github.com" \
        -c user.name="github-actions[bot]" \
        commit --quiet -m "$MSG" || exit 0
    git push --quiet origin gh-pages ) >&2 && { ok=true; break; }

  echo "gh-pages push attempt ${attempt} failed (likely a concurrent update); retrying..." >&2
  sleep $(( (RANDOM % 5) + 3 ))
done

rm -rf "$WORK"
$ok || { echo "::warning::could not publish the ${KIND} dashboard after 8 attempts"; }

# A `home` run has no per-service URL to print.
[ "$KIND" = "home" ] && { echo "dashboard home refreshed"; exit 0; }

URL="https://$(echo "$REPO_SLUG" | cut -d/ -f1).github.io/$(echo "$REPO_SLUG" | cut -d/ -f2)/security/trivy/${SERVICE}/?build=${BUILD}&kind=${KIND}"
echo "REPORT_URL=${URL}" >> "${GITHUB_OUTPUT:-/dev/null}"
echo "$URL"
