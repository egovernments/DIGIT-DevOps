#!/usr/bin/env bash
# 06 — bundle chart generation, bundle_db, tag pin, services deploy, Kong
# (INSTALL.md §4.2–4.4). Usage: ./06-deploy.sh <path-to-digit3-repo> [TAG]
# TAG defaults to scripts/.last-build-tag written by 05-build.sh.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel

[ $# -ge 1 ] || die "usage: $0 <path-to-digit3-repo> [image-tag]"
DIGIT3="$(cd "$1" && pwd)"
MANIFEST="$DIGIT3/src/bundles/dev-bundle.package.yaml"
TAG="${2:-$(cat "$SCRIPT_DIR/.last-build-tag" 2>/dev/null || true)}"
[ -n "$TAG" ] || die "no TAG given and scripts/.last-build-tag missing — run 05-build.sh first"

note "generating the bundle chart (+ deriving egov-service-host keys from the manifest)"
python3 "$HELM_DIR/bundler/generate_bundle_chart.py" --manifest "$MANIFEST" --service-hosts "$ENV_FILE" \
  | grep -E "^wrote|^service-host|^  [~+]" || true

note "re-rendering cluster-configs so the service-host map matches the shape"
"$DEPLOY" -f backboneservices-helmfile.yaml -l name=cluster-configs sync >/dev/null
echo "    cluster-configs synced"

note "bundle database"
if ! psql_exec -tAc "SELECT 1 FROM pg_database WHERE datname='bundle_db'" | grep -q 1; then
  psql_exec -c "CREATE DATABASE bundle_db"
else
  echo "    bundle_db exists"
fi

note "pinning image tags to $TAG in the dev-bundle block of azure-k3s.yaml"
python3 - "$ENV_FILE" "$TAG" <<'EOF'
import re, sys
path, tag = sys.argv[1], sys.argv[2]
lines = open(path).readlines()
in_block, changed = False, 0
for i, line in enumerate(lines):
    if re.match(r"^dev-bundle:", line):
        in_block = True
        continue
    if in_block and re.match(r"^\S", line):    # next top-level key ends the block
        in_block = False
    if in_block and re.match(r'^\s+tag:\s*"', line):
        lines[i] = re.sub(r'tag:\s*"[^"]*"', f'tag: "{tag}"', line)
        changed += 1
open(path, "w").writelines(lines)
print(f"    {changed} tag line(s) pinned")
assert changed >= 2, "expected the app + db-init tag lines inside the dev-bundle block"
EOF

note "deploying services (dev-bundle, keycloak, gateway-kong)"
"$DEPLOY" -f digit3services-helmfile.yaml sync
kubectl rollout status deploy/dev-bundle -n egov --timeout=300s

note "programming kong from the manifest"
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
sleep 3
(cd "$DIGIT3/src/services/kong" && KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS="$DOMAIN" python3 setup.py)

next "./07-seed.sh \"My Tenant\" admin@example.org --verify"
