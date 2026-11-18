#!/usr/bin/env bash
# Create digit-secrets.yaml: fresh random values for every <placeholder> in the template,
# encrypted with SOPS to the team's own Azure Key Vault key. Run by the workflow on the
# first install; never overwrites an existing file.
#
#   generate-secrets.sh <template> <output> <key-vault-key-id>
#
# Every value is new for every team, so no two installations share a password or key.
# The plaintext only exists in a 0600 temp file on the runner and is deleted on exit.
set -euo pipefail
tmpl=${1:?template}; out=${2:?output file}; kid=${3:?Azure Key Vault key id}
[ -e "$out" ] && { echo "$out already exists - not overwriting" >&2; exit 1; }
for c in sops python3; do command -v "$c" >/dev/null || { echo "$c not found" >&2; exit 1; }; done

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
plain="$work/digit-secrets.yaml"
( umask 077
  # Terraform rule for db_password: 6-16 chars, starts with a lowercase letter, letters/numbers only here
  python3 - "$tmpl" > "$plain" <<'PY'
import base64, secrets, string, sys, uuid
s = open(sys.argv[1]).read()
alnum = string.ascii_letters + string.digits
r = lambda n: ''.join(secrets.choice(alnum) for _ in range(n))
low = lambda n: ''.join(secrets.choice(string.ascii_lowercase) for _ in range(n))
vals = {
  'db_user': 'digitadmin',
  'db_password': secrets.choice(string.ascii_lowercase) + r(15),
  'minio_user': 'minio' + low(6),
  'minio_password': r(24),
  'kafka_cluster_id': base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip('='),
  'elasticsearch_password': r(24),
  'keycloak_admin_user': 'kcadmin' + low(4),
  'keycloak_admin_password': r(24),
  'keycloak_db_user': 'keycloak',
  'keycloak_db_password': r(24),
  'employee_iam_client_secret': r(32),
  'citizen_broker_client_secret': r(32),
  'hmac_secret': r(48),
  'grafana_admin_password': r(24),
  'argocd_admin_password': r(24),
}
for k, v in vals.items():
    assert s.count('<%s>' % k) == 1, k
    s = s.replace('<%s>' % k, v)
assert '<' not in s.split('secrets:', 1)[1], 'unfilled placeholder in template'
sys.stdout.write(s)
PY
)
sops --encrypt --azure-kv "$kid" "$plain" > "$out.tmp"
mv "$out.tmp" "$out"
[ "$(sops filestatus "$out")" = '{"encrypted":true}' ] || { rm -f "$out"; echo "encryption failed" >&2; exit 1; }
echo "Created $out (encrypted with $kid)"
