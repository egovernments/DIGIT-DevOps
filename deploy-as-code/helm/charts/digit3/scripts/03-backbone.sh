#!/usr/bin/env bash
# 03 — backbone deploy + Keycloak database AND role (INSTALL.md §1.6–1.7).
# Idempotent: sync converges; DB/role creation reconciles instead of failing.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel

note "deploying backbone (cluster-configs, cert-manager, ingress, postgres, redis, minio, kafka)"
"$DEPLOY" -f backboneservices-helmfile.yaml sync

# The first-ever sync races cert-manager's webhook: the ClusterIssuer applies
# fail with "no endpoints available" while helmfile still exits 0, leaving the
# cluster silently without issuers. Detect, wait for the webhook, re-sync just
# cert-manager, and fail LOUDLY if the issuers still don't exist.
if ! kubectl get clusterissuer letsencrypt-prod >/dev/null 2>&1; then
  note "ClusterIssuers missing (cert-manager webhook race) — waiting and re-syncing"
  kubectl wait --for=condition=Available deploy/cert-manager-webhook -n egov --timeout=180s
  "$DEPLOY" -f backboneservices-helmfile.yaml -l name=cert-manager sync
  kubectl get clusterissuer letsencrypt-prod >/dev/null 2>&1 || \
    die "ClusterIssuers still missing after cert-manager re-sync — see the gotchas table in INSTALL.md"
fi

# filestore's bucket: minio starts empty and the service reports NoSuchBucket
# on the first upload — provision it once here (idempotent: mb -p).
note "minio bucket for filestore"
kubectl exec -n backbone minio-0 -- sh -c \
  'mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc mb -p local/unified-dev-bucket-s3' \
  2>/dev/null | tail -1 || echo "    minio not ready yet — re-run this script (idempotent)"

note "waiting for postgres"
wait_for_pod egov statefulset.kubernetes.io/pod-name=postgresql-lts-0 300

note "keycloak database"
if ! psql_exec -tAc "SELECT 1 FROM pg_database WHERE datname='new_keycloak'" | grep -q 1; then
  psql_exec -c "CREATE DATABASE new_keycloak"
else
  echo "    new_keycloak exists"
fi

note "keycloak role (credentials from the kc-db secret; skipping this half is the classic crash-loop)"
KC_USER=$(kubectl get secret kc-db -n keycloak -o jsonpath='{.data.username}' | base64 -d)
KC_PASS=$(kubectl get secret kc-db -n keycloak -o jsonpath='{.data.password}' | base64 -d)
if psql_exec -tAc "SELECT 1 FROM pg_roles WHERE rolname='$KC_USER'" | grep -q 1; then
  printf "ALTER ROLE %s WITH LOGIN PASSWORD '%s';\n" "$KC_USER" "$KC_PASS" | psql_exec >/dev/null
  echo "    role '$KC_USER' exists — password reconciled with the secret"
else
  printf "CREATE ROLE %s LOGIN PASSWORD '%s';
GRANT ALL PRIVILEGES ON DATABASE new_keycloak TO %s;
ALTER DATABASE new_keycloak OWNER TO %s;\n" "$KC_USER" "$KC_PASS" "$KC_USER" "$KC_USER" | psql_exec
fi

next "./04-vault.sh   (or skip to ./06-deploy.sh <digit3> <shape> if not using Vault PII encryption)"
