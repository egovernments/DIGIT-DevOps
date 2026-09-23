#!/usr/bin/env bash
# 03 — backbone deploy + Keycloak database AND role (INSTALL.md §1.6–1.7).
# Idempotent: sync converges; DB/role creation reconciles instead of failing.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel

note "deploying backbone (cluster-configs, cert-manager, ingress, postgres, redis, minio, kafka)"
# First-ever sync installs cert-manager AND its ClusterIssuers in one pass; the
# validating webhook isn't serving yet, so the issuers fail. Known race
# (INSTALL.md §1.6). On a truly fresh cluster the failed release may leave the
# webhook deployment not-yet-created, so we can't just `kubectl wait` for it —
# retry the whole sync a few times, letting the webhook come up between tries.
SYNC_OK=false
for attempt in 1 2 3 4; do
  if OUT=$("$DEPLOY" -f backboneservices-helmfile.yaml sync 2>&1); then
    SYNC_OK=true
    printf '%s\n' "$OUT" | tail -8
    break
  fi
  if printf '%s' "$OUT" | grep -q 'webhook.cert-manager.io'; then
    note "cert-manager webhook not serving yet (attempt $attempt) — waiting for it, then re-syncing"
    # tolerate the deployment not existing yet: poll until it appears + is Available
    for _ in $(seq 1 30); do
      if kubectl get deploy cert-manager-webhook -n cert-manager >/dev/null 2>&1; then
        kubectl wait --for=condition=Available deploy/cert-manager-webhook -n cert-manager --timeout=120s >/dev/null 2>&1 && break
      fi
      sleep 5
    done
  else
    printf '%s\n' "$OUT" | tail -25
    die "backbone sync failed (full error above)"
  fi
done
$SYNC_OK || die "backbone sync still failing after retries — is cert-manager's webhook coming up? kubectl get pods -n cert-manager"

# filestore's bucket: minio starts empty and the service reports NoSuchBucket
# on the first upload — provision it once here (idempotent: mb -p).
note "minio bucket for filestore"
kubectl exec -n backbone minio-0 -- sh -c \
  'mc alias set local http://localhost:9000 "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null && mc mb -p local/unified-dev-bucket-s3' \
  2>/dev/null | tail -1 || echo "    minio not ready yet — re-run this script (idempotent)"

note "waiting for postgres"
wait_for_pod egov statefulset.kubernetes.io/pod-name=postgresql-lts-0 300
# Kafka carries the tenant-migration events; if its controller never comes up (a bad KRaft id, a
# storage problem) nothing notices until 07-seed's fan-out hangs — surface it here instead.
note "waiting for kafka"
wait_for_pod backbone statefulset.kubernetes.io/pod-name=release-name-kafka-controller-0 300

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

# Assert both objects exist before declaring the backbone done — a partial run
# (e.g. an earlier sync failure that exited before this block) otherwise leaves
# Keycloak crash-looping on 'password authentication failed for user keycloak'.
psql_exec -tAc "SELECT 1 FROM pg_database WHERE datname='new_keycloak'" | grep -q 1 \
  || die "new_keycloak database missing after creation — check postgres"
psql_exec -tAc "SELECT 1 FROM pg_roles WHERE rolname='$KC_USER'" | grep -q 1 \
  || die "keycloak role missing after creation — check postgres"
echo "    verified: new_keycloak database + $KC_USER role present"

# If Keycloak was already up but crash-looping on the missing role, nudge it so
# it retries with the now-valid credentials (no-op if it's healthy). And when we
# do recover it, restart any already-running Keycloak consumers: the account
# service builds its Keycloak admin client once at boot, so a service that
# started while Keycloak was down caches a dead connection and every later
# tenant-create fails with 'failed to get admin token: ConnectException'.
if kubectl get deploy keycloak -n keycloak >/dev/null 2>&1; then
  RESTARTS=$(kubectl get pods -n keycloak -l app=keycloak -o jsonpath='{.items[-1:].status.containerStatuses[0].restartCount}' 2>/dev/null || echo 0)
  READY=$(kubectl get deploy keycloak -n keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo 0)
  if [ "${RESTARTS:-0}" -gt 0 ] 2>/dev/null && [ "${READY:-0}" -lt 1 ] 2>/dev/null; then
    note "keycloak was crash-looping — restarting it, then waiting for it to serve"
    kubectl rollout restart deploy/keycloak -n keycloak >/dev/null
    kubectl rollout status deploy/keycloak -n keycloak --timeout=180s >/dev/null || true
    # restart whichever account-bearing deployment exists (any shape) so it
    # re-initializes its Keycloak admin client against the healthy instance
    for d in identity-bundle dev-bundle account; do
      if kubectl get deploy "$d" -n egov >/dev/null 2>&1; then
        note "restarting $d so it refreshes its Keycloak admin client"
        kubectl rollout restart "deploy/$d" -n egov >/dev/null
      fi
    done
  fi
fi

next "./04-vault.sh   (or skip to ./06-deploy.sh <digit3> <shape> if not using Vault PII encryption)"
