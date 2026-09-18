#!/usr/bin/env bash
# Deploy ONE shape declaratively: pick the shape's helmfile (which layers its
# environments/azure-k3s-<shape>.yaml overlay), pass the image tag as the
# single DIGIT_TAG input, and program kong from the same manifest that built
# the images. No environment file is mutated — switching shape later is just
# re-running this with the other shape (same domain = same overlay caveat:
# each shape's overlay pins its own domain; see INSTALL.md §4).
#
#   ./06-deploy.sh <path-to-digit3-repo> <services|dev-bundle|domain-split> [tag]
#
# tag defaults to scripts/.last-build-tag (written by 05-build.sh); for the
# Actions-built images pass it explicitly, e.g. modulith-39f619d.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel
[ $# -ge 2 ] || die "usage: $0 <path-to-digit3-repo> <services|dev-bundle|domain-split> [image-tag]"
DIGIT3="$(cd "$1" && pwd)"
SHAPE="$2"
TAG="${3:-$(cat "$SCRIPT_DIR/.last-build-tag" 2>/dev/null || true)}"
[ -n "$TAG" ] || die "no tag given and scripts/.last-build-tag missing — pass the Actions tag (modulith-<sha>) or run 05-build.sh"

case "$SHAPE" in
  services)
    HELMFILE=services-helmfile.yaml
    MANIFEST=""                                   # kong: per-service upstreams
    ROLLOUT="idgen account boundary" ;;           # spot-check three; the rest follow
  dev-bundle)
    HELMFILE=digit3services-helmfile.yaml
    MANIFEST="$DIGIT3/src/bundles/dev-bundle.package.yaml"
    ROLLOUT="dev-bundle" ;;
  domain-split)
    HELMFILE=domain-split-helmfile.yaml
    MANIFEST="$DIGIT3/src/bundles/domain-split.package.yaml"
    ROLLOUT="identity-bundle notification-bundle billing-bundle admin-bundle" ;;
  *) die "unknown shape '$SHAPE' (services|dev-bundle|domain-split)" ;;
esac

if [ -n "$MANIFEST" ]; then
  [ -f "$MANIFEST" ] || die "manifest not found: $MANIFEST"
  note "generating the bundle chart(s) from the manifest"
  python3 "$HELM_DIR/bundler/generate_bundle_chart.py" --manifest "$MANIFEST" | tail -1
fi

note "deploying shape '$SHAPE' with DIGIT_TAG=$TAG"
DIGIT_TAG="$TAG" "$DEPLOY" -f "$HELMFILE" sync
for d in $ROLLOUT; do
  kubectl rollout status "deploy/$d" -n egov --timeout=300s
done

note "programming kong from the manifest"
# kong just synced: wait for its deployment AND for the Admin API to answer —
# programming a starting kong loses routes silently.
kubectl rollout status deploy/kong-kong -n egov --timeout=300s >/dev/null
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 >/dev/null 2>&1 &
PF_PID=$!
trap 'kill $PF_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do
  curl -sfm 2 -o /dev/null http://localhost:18001/status && break
  sleep 2
done
curl -sfm 2 -o /dev/null http://localhost:18001/status || die "kong Admin API not answering on the port-forward"
case "$SHAPE" in
  services)     KONG_BUNDLES="none" ;;
  dev-bundle)   KONG_BUNDLES="" ;;                # setup.py default manifest
  domain-split) KONG_BUNDLES="$MANIFEST" ;;
esac
# `env` (not bare assignments): a ${VAR:+X=Y} expansion is NOT parsed as an
# assignment by bash — it becomes a command word and the line dies with
# "KONG_BUNDLE_MANIFESTS=none: command not found".
(cd "$DIGIT3/src/services/kong" && \
  env KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS="$DOMAIN" \
  ${KONG_BUNDLES:+KONG_BUNDLE_MANIFESTS="$KONG_BUNDLES"} python3 setup.py)

echo "$SHAPE" > "$SCRIPT_DIR/.last-shape"
next "./07-seed.sh \"My Tenant\" admin@example.org --verify"
