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

if [ -z "$(sops_get 'cluster-configs.secrets.vault-approle.role-id')" ]; then
  note "storing approle credentials in the sops file"
  sops_set "cluster-configs.secrets.vault-approle.role-id" \
    "$(vault_exec 'vault read -field=role_id auth/approle/role/digit-services/role-id')"
  sops_set "cluster-configs.secrets.vault-approle.secret-id" \
    "$(vault_exec 'vault write -f -field=secret_id auth/approle/role/digit-services/secret-id')"
  note "re-rendering the vault-approle k8s secret"
  "$DEPLOY" -f backboneservices-helmfile.yaml -l name=cluster-configs sync
else
  echo "    approle credentials already in the sops file"
fi

next "./05-build.sh <path-to-digit3-repo>"
