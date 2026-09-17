#!/usr/bin/env bash
# 02 — age key, .sops.yaml rule, fresh encrypted secrets file, domain stamped
# into the environment file (INSTALL.md §1.4–1.5).
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
  - path_regex: environments/azure-k3s-secrets\.yaml\$
    age: $RECIPIENT
EOF
else
  note ".sops.yaml already lists this recipient"
fi

if [ -f "$SECRETS_FILE" ]; then
  note "secrets file exists — leaving it untouched ($SECRETS_FILE)"
else
  note "generating $SECRETS_FILE with fresh credentials"
  rand() { openssl rand -base64 24 | tr -d '/+=' | cut -c1-24; }
  KRAFT_ID=$(python3 -c "import uuid,base64;print(base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip('='))")
  cat > "$SECRETS_FILE" <<EOF
cluster-configs:
  secrets:
    db:
      username: postgres
      password: $(rand)
      flywayUsername: postgres
      flywayPassword: $(rand)
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
