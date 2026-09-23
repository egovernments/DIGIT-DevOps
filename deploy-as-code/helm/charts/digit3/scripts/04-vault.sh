#!/usr/bin/env bash
# 04 — Vault: deploy, init/unseal, transit + AppRole, credentials into sops,
# cluster-configs re-sync (INSTALL.md §1.8). Idempotent — also the script to
# re-run after any Vault pod restart (Shamir seal closes on every restart).
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel

note "deploying vault"
"$DEPLOY" -f backboneservices-helmfile.yaml -l name=vault sync
until kubectl get pod vault-0 -n vault --no-headers 2>/dev/null | grep -q Running; do sleep 5; done

vstatus() { kubectl exec vault-0 -n vault -- vault status -format=json 2>/dev/null || true; }
INITIALIZED=$(vstatus | python3 -c "import sys,json;print(json.load(sys.stdin).get('initialized'))" 2>/dev/null || echo "")

if [ "$INITIALIZED" != "True" ] && [ "$INITIALIZED" != "true" ]; then
  note "initializing (1-of-1 Shamir) — keys go straight into the sops file, never onto disk"
  INIT_JSON=$(kubectl exec vault-0 -n vault -- vault operator init -key-shares=1 -key-threshold=1 -format=json)
  UNSEAL=$(printf '%s' "$INIT_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['unseal_keys_b64'][0])")
  ROOT=$(printf '%s' "$INIT_JSON" | python3 -c "import sys,json;print(json.load(sys.stdin)['root_token'])")
  unset INIT_JSON
  sops_set "vault-operator.unseal-key" "$UNSEAL"
  sops_set "vault-operator.root-token" "$ROOT"
  unset ROOT
else
  UNSEAL=$(sops_get "vault-operator.unseal-key")
  [ -n "$UNSEAL" ] || die "vault is initialized but vault-operator.unseal-key is empty in the sops file"
fi

SEALED=$(vstatus | python3 -c "import sys,json;print(json.load(sys.stdin).get('sealed'))" 2>/dev/null || echo True)
if [ "$SEALED" != "False" ] && [ "$SEALED" != "false" ]; then
  note "unsealing"
  printf '%s' "$UNSEAL" | kubectl exec -i vault-0 -n vault -- sh -c 'read -r K; vault operator unseal "$K"' | grep -E "^Sealed" || true
fi
unset UNSEAL
wait_for_pod vault app.kubernetes.io/name=vault 120

note "transit engine + approle (skips whatever already exists)"
vault_exec 'vault secrets list -format=json' | grep -q '"transit/"' || vault_exec 'vault secrets enable transit'
vault_exec 'vault auth list -format=json' | grep -q '"approle/"' || vault_exec 'vault auth enable approle'
# The mount's default max_lease_ttl is 768h; without raising it Vault silently
# truncates the role's 2160h token_max_ttl to 768h (it warns, the script went on).
vault_exec 'vault auth tune -max-lease-ttl=2160h approle/' >/dev/null
# Full transit baseline: encrypt/decrypt (otp, individual PII), sign/verify +
# key management (registry's audit signing, per-tenant ed25519 keys), and
# token self-renewal so long-lived service tokens don't silently expire.
vault_exec 'vault policy write digit-transit - <<EOF
path "transit/encrypt/*"     { capabilities = ["create","update"] }
path "transit/decrypt/*"     { capabilities = ["update"] }
path "transit/sign/*"        { capabilities = ["create","update"] }
path "transit/verify/*"      { capabilities = ["create","update"] }
path "transit/keys/*"        { capabilities = ["create","read","update","list","delete"] }
path "auth/token/renew-self" { capabilities = ["update"] }
EOF' >/dev/null
vault_exec 'vault write auth/approle/role/digit-services token_policies=digit-transit token_ttl=720h token_max_ttl=2160h' >/dev/null

# Stored creds are only trusted after they LOG IN to THIS vault: the sops file
# is shared state, and values minted by a previous vault instance (another
# environment, a re-created server) look present but are dead — the classic
# symptom is otp crash-looping on AppRole login 400. Invalid or absent creds
# are re-minted and re-stored.
STORED_ROLE_ID=$(sops_get 'cluster-configs.secrets.vault-approle.role-id')
STORED_SECRET_ID=$(sops_get 'cluster-configs.secrets.vault-approle.secret-id')
CREDS_OK=false
if [ -n "$STORED_ROLE_ID" ] && [ -n "$STORED_SECRET_ID" ]; then
  if printf '{"role_id":"%s","secret_id":"%s"}' "$STORED_ROLE_ID" "$STORED_SECRET_ID" | \
     kubectl exec -i vault-0 -n vault -- sh -c \
       'wget -qO- --post-data="$(cat)" --header="Content-Type: application/json" http://127.0.0.1:8200/v1/auth/approle/login 2>/dev/null' \
     | grep -q '"client_token"'; then
    CREDS_OK=true
  fi
fi
unset STORED_ROLE_ID STORED_SECRET_ID
if $CREDS_OK; then
  echo "    approle credentials in the sops file log in against this vault — kept"
else
  note "storing approle credentials in the sops file (absent or minted by a different vault instance)"
  sops_set "cluster-configs.secrets.vault-approle.role-id" \
    "$(vault_exec 'vault read -field=role_id auth/approle/role/digit-services/role-id')"
  sops_set "cluster-configs.secrets.vault-approle.secret-id" \
    "$(vault_exec 'vault write -f -field=secret_id auth/approle/role/digit-services/secret-id')"
  note "re-rendering the vault-approle k8s secret"
  # cluster-configs carries BOTH the vault-approle secret and the shape
  # overlay's egov-service-host map. Re-syncing it from the backbone helmfile
  # applies base values only, which would silently revert every bundled
  # service's host to its per-service DNS name and point cross-bundle calls at
  # pods that do not exist. Before any shape is deployed the base values are
  # correct; afterwards, re-sync through that shape's own helmfile.
  # 06-deploy.sh records the shape; a custom grouping writes .last-shape itself
  # (CUSTOM-BUNDLING.md §6).
  CC_HELMFILE=backboneservices-helmfile.yaml
  LAST_SHAPE=$(cat "$SCRIPT_DIR/.last-shape" 2>/dev/null || true)
  if [ -n "$LAST_SHAPE" ] && [ -f "$CHART_DIR/$LAST_SHAPE-helmfile.yaml" ]; then
    CC_HELMFILE="$LAST_SHAPE-helmfile.yaml"
    echo "    re-syncing cluster-configs via $CC_HELMFILE (keeps the $LAST_SHAPE service-host map)"
  fi
  # No DIGIT_TAG needed: -l name=cluster-configs renders only that release's
  # values, and cluster-configs takes no image.
  "$DEPLOY" -f "$CC_HELMFILE" -l name=cluster-configs sync
fi

next "./06-deploy.sh <path-to-digit3-repo> <single-container|domain-bundles|per-service> <tag>   (05-build.sh only for locally-built bundle images)"
