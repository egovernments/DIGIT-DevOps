#!/usr/bin/env bash
# 03 — backbone deploy + Keycloak database AND role (INSTALL.md §1.6–1.7).
# Idempotent: sync converges; DB/role creation reconciles instead of failing.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel

note "deploying backbone (cluster-configs, cert-manager, ingress, postgres, redis, minio, kafka)"
# First-ever sync installs cert-manager AND its ClusterIssuers in one pass;
# the validating webhook isn't serving yet, so the issuers fail. Known race
# (INSTALL.md §1.6) — wait for the webhook and retry once automatically.
if ! OUT=$("$DEPLOY" -f backboneservices-helmfile.yaml sync 2>&1); then
  if printf '%s' "$OUT" | grep -q 'webhook.cert-manager.io'; then
    note "first-run race: cert-manager webhook not serving yet — waiting, then retrying once"
    kubectl wait --for=condition=Available deploy/cert-manager-webhook -n cert-manager --timeout=180s >/dev/null
    "$DEPLOY" -f backboneservices-helmfile.yaml sync
  else
    printf '%s\n' "$OUT" | tail -25
    die "backbone sync failed (full error above)"
  fi
else
  printf '%s\n' "$OUT" | tail -8
fi

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

next "./04-vault.sh   (or skip to ./05-build.sh if not using Vault PII encryption)"
