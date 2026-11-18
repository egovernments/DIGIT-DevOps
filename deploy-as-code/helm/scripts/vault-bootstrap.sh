#!/usr/bin/env bash
# shellcheck disable=SC2016  # single-quoted commands are expanded by the shell inside the vault pod
# Vault bootstrap for the DIGIT one-click install (helmfile postsync hook of release "vault").
#
#   vault-bootstrap.sh <vault-namespace> <core-namespace>
#
# Idempotent - safe on every deploy:
#   1. init Vault once (1 key share) and keep unseal key + root token in Secret
#      <vault-ns>/vault-unseal (the vault pod mounts it and unseals itself on restart)
#   2. unseal if sealed
#   3. enable transit + approle, policy digit-transit, role digit-services
#   4. write Secret <core-ns>/vault-approle (role-id/secret-id) unless the existing pair
#      still logs in to THIS Vault; restart otp/individual when it changes
# Secret material never goes on argv or into logs (masked in GitHub Actions).
set -euo pipefail
VNS=${1:?vault namespace}; CNS=${2:?core namespace}
POD=vault-0
log() { echo "[vault-bootstrap] $*"; }
mask() { [ -n "${GITHUB_ACTIONS:-}" ] && [ -n "$1" ] && echo "::add-mask::$1"; true; }

# VAULT_WAIT_SECONDS: how long to wait for the pod (Argo CD mode creates it later than helmfile)
log "waiting for $VNS/$POD"
for _ in $(seq 1 $(( ${VAULT_WAIT_SECONDS:-450} / 5 ))); do
  [ "$(kubectl -n "$VNS" get pod "$POD" -o jsonpath='{.status.containerStatuses[0].started}' 2>/dev/null)" = "true" ] && break
  sleep 5
done
status() { kubectl -n "$VNS" exec "$POD" -- vault status -format=json 2>/dev/null || true; }
field() { python3 -c "import sys,json; print(str(json.load(sys.stdin).get('$1','')).lower())"; }
for _ in $(seq 1 30); do [ -n "$(status)" ] && break; sleep 3; done

if [ "$(status | field initialized)" != "true" ]; then
  log "initializing (1 key share) -> Secret $VNS/vault-unseal"
  INIT=$(kubectl -n "$VNS" exec "$POD" -- vault operator init -key-shares=1 -key-threshold=1 -format=json)
  KEY=$(printf '%s' "$INIT" | python3 -c "import sys,json; print(json.load(sys.stdin)['unseal_keys_b64'][0])")
  ROOT=$(printf '%s' "$INIT" | python3 -c "import sys,json; print(json.load(sys.stdin)['root_token'])")
  unset INIT; mask "$KEY"; mask "$ROOT"
  printf 'unseal-key=%s\nroot-token=%s\n' "$KEY" "$ROOT" |
    kubectl -n "$VNS" create secret generic vault-unseal --from-env-file=/dev/stdin --dry-run=client -o yaml |
    kubectl apply -f - >/dev/null
fi
getsec() { kubectl -n "$1" get secret "$2" -o jsonpath="{.data.$3}" 2>/dev/null | base64 -d; }
KEY=$(getsec "$VNS" vault-unseal unseal-key); ROOT=$(getsec "$VNS" vault-unseal root-token)
if [ -z "$KEY" ] || [ -z "$ROOT" ]; then echo "Vault is initialized but $VNS/vault-unseal is missing - restore it" >&2; exit 1; fi
mask "$KEY"; mask "$ROOT"

if [ "$(status | field sealed)" = "true" ]; then
  log "unsealing"
  printf '%s\n' "$KEY" | kubectl -n "$VNS" exec -i "$POD" -- sh -c 'read -r K; vault operator unseal "$K" >/dev/null'
fi
unset KEY

# Run a vault CLI command with the root token passed on stdin.
v() { printf '%s\n' "$ROOT" | kubectl -n "$VNS" exec -i "$POD" -- sh -c "read -r VAULT_TOKEN; export VAULT_TOKEN; $1"; }

log "transit + approle"
v 'vault secrets list -format=json' | grep -q '"transit/"' || v 'vault secrets enable transit' >/dev/null
v 'vault auth list -format=json' | grep -q '"approle/"' || v 'vault auth enable approle' >/dev/null
v 'vault auth tune -max-lease-ttl=2160h approle/' >/dev/null
v 'vault policy write digit-transit - <<EOF
path "transit/encrypt/*"     { capabilities = ["create","update"] }
path "transit/decrypt/*"     { capabilities = ["update"] }
path "transit/sign/*"        { capabilities = ["create","update"] }
path "transit/verify/*"      { capabilities = ["create","update"] }
path "transit/keys/*"        { capabilities = ["create","read","update","list","delete"] }
path "auth/token/renew-self" { capabilities = ["update"] }
EOF' >/dev/null
v 'vault write auth/approle/role/digit-services token_policies=digit-transit token_ttl=720h token_max_ttl=2160h' >/dev/null

ROLE=$(getsec "$CNS" vault-approle role-id || true); SID=$(getsec "$CNS" vault-approle secret-id || true)
mask "$SID"
if [ -n "$ROLE" ] && [ -n "$SID" ] && printf '{"role_id":"%s","secret_id":"%s"}' "$ROLE" "$SID" |
     kubectl -n "$VNS" exec -i "$POD" -- sh -c 'wget -qO- --post-data="$(cat)" --header="Content-Type: application/json" http://127.0.0.1:8200/v1/auth/approle/login' 2>/dev/null |
     grep -q client_token; then
  log "vault-approle in $CNS logs in to this Vault - kept"
else
  log "writing $CNS/vault-approle"
  ROLE=$(v 'vault read -field=role_id auth/approle/role/digit-services/role-id')
  SID=$(v 'vault write -f -field=secret_id auth/approle/role/digit-services/secret-id'); mask "$SID"
  printf 'role-id=%s\nsecret-id=%s\n' "$ROLE" "$SID" |
    kubectl -n "$CNS" create secret generic vault-approle --from-env-file=/dev/stdin --dry-run=client -o yaml |
    kubectl apply -f - >/dev/null
  for d in otp individual; do
    kubectl -n "$CNS" get deploy "$d" >/dev/null 2>&1 && kubectl -n "$CNS" rollout restart deploy "$d" >/dev/null && log "restarted $d"
  done
fi
unset ROOT SID
log "done"
