#!/bin/bash
# Test-only: build the four LnP UI images for ONE domain. The UIs bake every VITE_* URL in at build time, so
# each VM needs its own images; they are never pushed — deploy-local-ui.sh imports them into the VM's containerd.
#   build-ui.sh <license-certificate-ui checkout> <domain> <tag>
#   e.g. build-ui.sh ~/license-certificate-ui-build/services/license-certificate-ui modulith-test.digit.org lnp-local-test
set -u; W=$1; DOMAIN=$2; TAG=$3; cd "$W" || exit 1
COMMON=(--build-arg VITE_KEYCLOAK_URL=https://$DOMAIN/keycloak --build-arg VITE_KEYCLOAK_DIRECT_URL=https://$DOMAIN/keycloak
        --build-arg VITE_KEYCLOAK_ENABLED=true --build-arg VITE_TENANT_ID=BASETENANT --build-arg VITE_KEYCLOAK_REALM=BASETENANT
        --build-arg VITE_FILESTORE_DOCUMENT_MODULE=default --build-arg VITE_MASTER_TENANT_ID=BASETENANT --build-arg VITE_API_BASE_URL=https://$DOMAIN)
for app in admin citizen employee validator; do
  t0=$SECONDS; echo "== build license-$app ($(date +%H:%M:%S))"
  docker --context desktop-linux buildx build --platform linux/amd64 --load -t egovio/license-$app:$TAG -f docker/Dockerfile.$app \
    "${COMMON[@]}" --build-arg VITE_KEYCLOAK_CLIENT_ID=$app . > /tmp/lnp-ui-build-$app.log 2>&1 \
    && echo "   ok  ($((SECONDS-t0))s)" || { echo "   FAIL ($((SECONDS-t0))s) — tail:"; tail -15 /tmp/lnp-ui-build-$app.log | cut -c1-200; }
done; echo "== BUILDS DONE"
