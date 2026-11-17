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
  note "adding a creation rule for this environment's secrets file to .sops.yaml"
  # sops applies the FIRST matching rule, and the shared azure-k3s rule already matches every
  # per-environment file with another team's key. So the new rule names this domain's file
  # exactly and goes in front of it, indented like the existing list items (appending at a
  # different indent made the YAML invalid and sops refused to load it).
  python3 - "$SOPS_RULES" "$DOMAIN" "$RECIPIENT" <<'PY'
import os, re, sys
path, domain, recipient = sys.argv[1:]
lines = open(path).read().splitlines() if os.path.exists(path) else []
if not any(l.strip() == "creation_rules:" for l in lines):
    lines.append("creation_rules:")
regex = r"environments/azure\-k3s\-secrets\." + re.escape(domain).replace("-", r"\-") + r"\.yaml$"
items = [i for i, l in enumerate(lines) if l.lstrip().startswith("- path_regex:")]
first_k3s = next((i for i in items if "azure" in lines[i] and "k3s" in lines[i]), None)
at = first_k3s if first_k3s is not None else (items[0] if items else len(lines))
indent = re.match(r"\s*", lines[at]).group(0) if at < len(lines) else "  "
lines[at:at] = [f"{indent}- path_regex: {regex}", f"{indent}  age: '{recipient}'"]
open(path, "w").write("\n".join(lines) + "\n")
PY
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
  # KRaft cluster id: base64url of a random uuid (22 chars). Never let it start with '-' — the Bitnami
  # entrypoint passes it as `kafka-storage format --cluster-id <id>` and argparse reads a leading '-'
  # as an option, so Kafka crash-loops forever (seen 2026-09-22: id "-0KdtnE8TAuMLCjuNSMtdg").
  KRAFT_ID=$(python3 -c "
import uuid,base64
while True:
    i=base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip('=')
    if i[0] not in '-_': print(i); break")
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
    vault-approle:            # filled by 04-openbao.sh
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
vault-operator:               # filled by 04-openbao.sh
  unseal-key: ""
  root-token: ""
EOF
  (cd "$HELM_DIR" && sops -e -i "$SECRETS_FILE")
  note "encrypted in place"
fi

# Domain is NOT stamped into any env file: deploy.sh passes the VM's domain from
# scripts/.env as global.domain to every release, so the base azure-k3s.yaml and
# the shape overlays stay domain-neutral in effect.

next "./03-backbone.sh"
