#!/usr/bin/env bash
# 06 — deploy a shape: (re)generate its bundle charts, derive the
# egov-service-host map, ensure the database, pin image tags if a local build
# happened, sync the shape's helmfile, program Kong (INSTALL.md §4.2–4.4).
#
# Usage: ./06-deploy.sh [--shape single-container|domain-bundles|per-service] <digit3-path> [TAG]
#   TAG default: scripts/.last-build-tag (written by 05-build.sh); with neither,
#   the tags already pinned in the environment file are used as-is.
# Deploy exactly ONE shape at a time — switching shapes: uninstall the old
# shape's releases first (helm uninstall), then run this for the new shape.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel

SHAPE="$(current_shape)"
if [ "${1:-}" = "--shape" ]; then SHAPE="$2"; shift 2; fi
HELMFILE="$(shape_helmfile "$SHAPE")"

[ $# -ge 1 ] || die "usage: $0 [--shape <shape>] <digit3-path> [TAG]"
DIGIT3="$(cd "$1" && pwd)"
MANIFEST="$(shape_manifest "$DIGIT3" "$SHAPE")"
TAG="${2:-$(cat "$SCRIPT_DIR/.last-build-tag" 2>/dev/null || true)}"
set_env_var SHAPE "$SHAPE"
note "shape: $SHAPE (helmfile: $HELMFILE)"

if [ "$SHAPE" = "per-service" ]; then
  note "deriving per-service egov-service-host keys from the manifest"
  python3 "$HELM_DIR/bundler/generate_bundle_chart.py" --manifest "$MANIFEST" \
    --service-hosts "$ENV_FILE" --service-hosts-mode per-service | grep -E "^service-host|^  [~+]" || true
else
  note "regenerating bundle chart(s) + deriving egov-service-host keys from the manifest"
  FIRST=true
  for b in $(shape_bundles "$SHAPE"); do
    if $FIRST; then
      python3 "$HELM_DIR/bundler/generate_bundle_chart.py" --manifest "$MANIFEST" --bundle "$b" \
        --service-hosts "$ENV_FILE" | grep -E "^wrote|^service-host|^  [~+]" || true
      FIRST=false
    else
      python3 "$HELM_DIR/bundler/generate_bundle_chart.py" --manifest "$MANIFEST" --bundle "$b" \
        | grep -E "^wrote" || true
    fi
  done
fi

note "re-rendering cluster-configs so the service-host map matches the shape"
"$DEPLOY" -f backboneservices-helmfile.yaml -l name=cluster-configs sync >/dev/null
echo "    cluster-configs synced"

if [ "$SHAPE" != "per-service" ]; then
  note "bundle database"
  if ! psql_exec -tAc "SELECT 1 FROM pg_database WHERE datname='bundle_db'" | grep -q 1; then
    psql_exec -c "CREATE DATABASE bundle_db"
  else
    echo "    bundle_db exists"
  fi
fi

if [ "$SHAPE" = "per-service" ]; then
  # per-service images are pinned per block (mixed registries/tags from the
  # reference deployment) — never mass-pin one tag across them
  TAG=""
fi
if [ -n "$TAG" ]; then
  BLOCKS="$(shape_bundles "$SHAPE")"
  note "pinning image tags to $TAG in the $SHAPE block(s) of azure-k3s.yaml"
  python3 - "$ENV_FILE" "$TAG" $BLOCKS <<'EOF'
import re, sys
path, tag, blocks = sys.argv[1], sys.argv[2], set(sys.argv[3:])
lines = open(path).readlines()
in_block, changed = False, 0
for i, line in enumerate(lines):
    m_top = re.match(r"^([A-Za-z0-9-]+):", line)
    if m_top:
        in_block = m_top.group(1) in blocks
        continue
    if in_block and re.match(r'^\s+tag:\s*"', line):
        lines[i] = re.sub(r'tag:\s*"[^"]*"', f'tag: "{tag}"', line)
        changed += 1
open(path, "w").writelines(lines)
print(f"    {changed} tag line(s) pinned across {len(blocks)} block(s)")
assert changed >= len(blocks), "expected at least one tag line per release block"
EOF
else
  note "no build tag recorded — keeping the tags already pinned in azure-k3s.yaml"
fi

note "deploying the $SHAPE shape"
"$DEPLOY" -f "$HELMFILE" sync
if [ "$SHAPE" = "per-service" ]; then
  kubectl wait --for=condition=Available deploy --all -n egov --timeout=600s >/dev/null && echo "    all deployments Available"
else
  for b in $(shape_bundles "$SHAPE"); do
    kubectl rollout status "deploy/$b" -n egov --timeout=300s
  done
fi

note "programming kong from the manifest"
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 3
KONG_MANIFESTS="$MANIFEST"
[ "$SHAPE" = "per-service" ] && KONG_MANIFESTS="none"
(cd "$DIGIT3/src/services/kong" && \
  KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS="$DOMAIN" \
  KONG_BUNDLE_MANIFESTS="$KONG_MANIFESTS" python3 setup.py)

next "./07-seed.sh \"My Tenant\" admin@example.org --verify"
