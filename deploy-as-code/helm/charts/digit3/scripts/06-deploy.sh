#!/usr/bin/env bash
# Deploy ONE shape declaratively: pick the shape's helmfile (which layers its
# environments/azure-k3s-<shape>.yaml overlay), pass the image tag as the
# single DIGIT_TAG input, and program kong from the same manifest that built
# the images. No environment file is mutated — switching shape later is just
# re-running this with the other shape (same domain = same overlay caveat:
# each shape's overlay pins its own domain; see INSTALL.md §4).
#
#   ./06-deploy.sh <path-to-digit3-repo> <single-container|domain-bundles|per-service|<path>/<name>.package.yaml> [tag]
#
# tag defaults to scripts/.last-build-tag (written by 05-build.sh); for the
# Actions-built images pass it explicitly, e.g. modulith-39f619d.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel
[ $# -ge 2 ] || die "usage: $0 <path-to-digit3-repo> <single-container|domain-bundles|per-service|<path>/<name>.package.yaml> [image-tag]"
DIGIT3="$(cd "$1" && pwd)"
resolve_shape "$DIGIT3" "$2"
TAG="${3:-$(cat "$SCRIPT_DIR/.last-build-tag" 2>/dev/null || true)}"
[ -n "$TAG" ] || die "no tag given and scripts/.last-build-tag missing — pass the Actions tag (modulith-<sha>) or run 05-build.sh"
ROLLOUT=${BUNDLES:-"idgen account boundary"}      # per-service: spot-check three; the rest follow

if [ -n "$MANIFEST" ]; then
  # one run writes the bundle charts AND this shape's helmfile, bundle values and service-host map
  note "generating the bundle charts, helmfile and shape values from $(basename "$MANIFEST")"
  python3 "$HELM_DIR/bundler/generate_bundle_chart.py" --manifest "$MANIFEST" | grep -E '^wrote (environments|charts/digit3)|WARNING'
  OVERLAY="$HELM_DIR/environments/azure-k3s-$SHAPE.yaml"
  if [ ! -f "$OVERLAY" ]; then   # custom grouping: the overlay only carries the domain + real environment choices
    printf '# Shape overlay for %s — domain and real environment choices only; bundle values, the\n# service-host map and the helmfile are generated from the manifest.\nglobal:\n  domain: %s\n' "$SHAPE" "$DOMAIN" > "$OVERLAY"
    note "wrote $(basename "$OVERLAY") (domain only) — commit it with the manifest"
  fi
  owner_of_services "$MANIFEST" > "$SCRIPT_DIR/.last-owners"
else
  printf 'ACCOUNT_SVC=account\nIDGEN_SVC=idgen\nINDIVIDUAL_SVC=individual\nNOTIFICATION_SVC=notification\nOTP_SVC=otp\n' > "$SCRIPT_DIR/.last-owners"
fi

note "checking secrets: local file vs cluster (cluster-configs)"
DIGIT_TAG="$TAG" secrets_drift_check "$HELMFILE" || die "secrets mismatch — nothing deployed"

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
# One successful /status is the signal. A second bare check after the loop used
# to kill the phase on a transient port-forward drop seconds after kong was
# Ready; setup.py retries transient errors itself. Re-spawn the forward if it dies.
KONG_UP=false
for _ in $(seq 1 45); do
  kill -0 $PF_PID 2>/dev/null || { kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 >/dev/null 2>&1 & PF_PID=$!; sleep 2; }
  curl -sfm 2 -o /dev/null http://localhost:18001/status && { KONG_UP=true; break; }
  sleep 2
done
$KONG_UP || die "kong Admin API not answering after 3 min — check: kubectl get pods -n egov -l app.kubernetes.io/name=kong"
case "$SHAPE" in
  per-service)      KONG_BUNDLES="none" ;;
  single-container) KONG_BUNDLES="" ;;            # setup.py default manifest
  *)                KONG_BUNDLES="$MANIFEST" ;;   # domain-bundles and any custom grouping
esac
# `env` (not bare assignments): a ${VAR:+X=Y} expansion is NOT parsed as an
# assignment by bash — it becomes a command word and the line dies with
# "KONG_BUNDLE_MANIFESTS=none: command not found".
# Hosts: the public domain AND kong's in-cluster names. Re-programming the routes with the public
# domain only would strand anything that calls back into kong from inside the cluster (through
# kong-kong-proxy.egov).
KONG_HOSTS="$DOMAIN,kong-kong-proxy.egov.svc.cluster.local,kong-kong-proxy.egov"
(cd "$DIGIT3/src/services/kong" && \
  env KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS="$KONG_HOSTS" \
  ${KONG_BUNDLES:+KONG_BUNDLE_MANIFESTS="$KONG_BUNDLES"} python3 setup.py)

echo "$SHAPE" > "$SCRIPT_DIR/.last-shape"
next "./07-seed.sh \"My Tenant\" admin@example.org --verify"
