#!/usr/bin/env bash
# 03 — backbone deploy + Keycloak database AND role (INSTALL.md §1.6–1.7).
# Idempotent: sync converges; DB/role creation reconciles instead of failing.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel

note "deploying backbone (cluster-configs, cert-manager, ingress, postgres, redis, minio, kafka)"
"$DEPLOY" -f backboneservices-helmfile.yaml sync

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
