#!/usr/bin/env bash
# 02 — age key, .sops.yaml rule, fresh encrypted per-environment secrets file
# (INSTALL.md §1.4–1.5). The domain is owned by the shape overlays, not stamped here.
# Idempotent: reuses an existing age key and never overwrites an existing
# secrets file.
source "$(dirname "$0")/lib.sh"
load_env

AGE_KEY="$HOME/.config/sops/age/keys.txt"

if [ -f "$AGE_KEY" ]; then
  note "reusing existing age key ($AGE_KEY)"
else
  note "generating age key"
  mkdir -p "$(dirname "$AGE_KEY")"
  age-keygen -o "$AGE_KEY"
fi
if [ "$(uname)" = "Darwin" ]; then   # macOS sops looks elsewhere
  mkdir -p "$HOME/Library/Application Support/sops/age"
  ln -sf "$AGE_KEY" "$HOME/Library/Application Support/sops/age/keys.txt"
fi
RECIPIENT=$(age-keygen -y "$AGE_KEY")
echo
echo "  *** BACK UP $AGE_KEY OFF THIS MACHINE — it is the only key to the secrets ***"
echo "  recipient: $RECIPIENT"
echo

SOPS_RULES="$HELM_DIR/.sops.yaml"
if ! grep -q "$RECIPIENT" "$SOPS_RULES" 2>/dev/null; then
  note "adding creation rule to .sops.yaml"
  [ -f "$SOPS_RULES" ] && grep -q "creation_rules:" "$SOPS_RULES" || echo "creation_rules:" >> "$SOPS_RULES"
  cat >> "$SOPS_RULES" <<EOF
  - path_regex: environments/azure\-k3s\-secrets(\..*)?\.yaml\$
    age: $RECIPIENT
EOF
else
  note ".sops.yaml already lists this recipient"
fi
# Existing installs carry the pre-per-env rule — widen it in place (idempotent).
python3 - "$SOPS_RULES" <<'PY'
import sys
f = sys.argv[1]
s = open(f).read()
old = r'environments/azure\-k3s\-secrets\.yaml$'
new = r'environments/azure\-k3s\-secrets(\..*)?\.yaml$'
if new not in s and old in s:
    open(f, 'w').write(s.replace(old, new, 1))
    print("==> widened the .sops.yaml rule to cover per-env secrets files")
PY

# Per-environment file: each cluster gets its own credentials (and its own
# vault-operator/vault-approle entries — one shared file across environments
# means one vault's unseal key overwrites another's). load_env already picked
# the per-env path when the file exists; create it here when it doesn't.
PERENV_FILE="$HELM_DIR/environments/azure-k3s-secrets.$DOMAIN.yaml"
if [ "$SECRETS_FILE" != "$PERENV_FILE" ] && [ ! -f "$PERENV_FILE" ]; then
  SECRETS_FILE="$PERENV_FILE"
fi
if [ -f "$SECRETS_FILE" ]; then
  note "secrets file exists — leaving it untouched ($SECRETS_FILE)"
else
  note "generating $SECRETS_FILE with fresh credentials"
  rand() { openssl rand -base64 24 | tr -d '/+=' | cut -c1-24; }
  DB_PASS=$(rand)
  KRAFT_ID=$(python3 -c "import uuid,base64;print(base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip('='))")
  cat > "$SECRETS_FILE" <<EOF
cluster-configs:
  secrets:
    db:
      username: postgres
      password: $DB_PASS
      flywayUsername: postgres
      # SAME credential: flyway connects AS the postgres user — an independent
      # random here fails every -db init container (28P01) on fresh installs
      flywayPassword: $DB_PASS
    minio:
      accesskey: $(openssl rand -hex 10)
      secretkey: $(openssl rand -hex 20)
    kc-db:
      username: keycloak
      password: $(rand)
    kc-admin:
      username: digit
      password: $(rand)
    citizen-broker-secret:
      citizen-broker-client-secret: $(openssl rand -hex 16)
    employee-iam-secret:
      employee-iam-client-secret: $(openssl rand -hex 16)
    hmac-secret:
      hmac-secret: $(openssl rand -base64 36 | tr -d '/+=')
    vault-approle:            # filled by 04-vault.sh
      role-id: ""
      secret-id: ""
    egov-pg-service:
      stripe-secret-key: sk_test_placeholder
    egov-notification-mail:
      mailsenderusername: smtp-user-placeholder
      mailsenderpassword: smtp-pass-placeholder
    egov-notification-sms:
      username: sms-user
      password: sms-pass-placeholder
    kafka-kraft:
      kraft-cluster-id: $KRAFT_ID
vault-operator:               # filled by 04-vault.sh
  unseal-key: ""
  root-token: ""
EOF
  (cd "$HELM_DIR" && sops -e -i "$SECRETS_FILE")
  note "encrypted in place"
fi

# Domain is NOT stamped into the base env file: each shape overlay
# (environments/azure-k3s-<shape>.yaml) owns its own global.domain, layered by
# that shape's helmfile. If your VM's domain differs from the overlay's, edit
# the overlay — the base azure-k3s.yaml stays shape-neutral.

next "./03-backbone.sh"
