#!/usr/bin/env bash
# Create <env>-secrets.yaml from the secrets template: every <placeholder> gets a fresh random
# value (the same placeholder gets the same value everywhere, e.g. MinIO root login =
# filestore S3 key), then the file is locked with SOPS and the team's Azure Key Vault key.
# Run by the workflow on the first install; never overwrites an existing file.
#
#   generate-secrets.sh <template> <output> <key-vault-key-id>
#
# The plaintext only exists in a 0600 temp file on the runner and is deleted on exit.
set -euo pipefail
tmpl=${1:?template}; out=${2:?output file}; kid=${3:?Azure Key Vault key id}
[ -e "$out" ] && { echo "$out already exists - not overwriting" >&2; exit 1; }
for c in sops python3; do command -v "$c" >/dev/null || { echo "$c not found" >&2; exit 1; }; done

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
plain="$work/secrets.yaml"
( umask 077
  python3 - "$tmpl" > "$plain" <<'PY'
import base64, re, secrets, string, sys, uuid
s = open(sys.argv[1]).read()
alnum = string.ascii_letters + string.digits
r = lambda n: ''.join(secrets.choice(alnum) for _ in range(n))
low = lambda n: ''.join(secrets.choice(string.ascii_lowercase) for _ in range(n))
special = {
  # Terraform rule: 6-16 chars, starts with a lowercase letter, letters/numbers
  'db_password': lambda: secrets.choice(string.ascii_lowercase) + r(15),
  'kafka_cluster_id': lambda: base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip('='),
  'minio_user': lambda: 'minio' + low(6),
  'keycloak_admin_user': lambda: 'kcadmin' + low(4),
  'hmac_secret': lambda: r(48),
}
vals = {}
def fill(m):
    k = m.group(1)
    if k not in vals:
        vals[k] = special.get(k, lambda: r(24))()
    return vals[k]
out = []
for line in s.splitlines(keepends=True):
    if line.lstrip().startswith('#'):
        out.append(line); continue
    out.append(re.sub(r'<([a-z_]+)>', fill, line))
s = ''.join(out)
left = [l for l in s.splitlines() if not l.lstrip().startswith('#') and re.search(r'<[a-z_]+>', l)]
assert not left, 'unfilled placeholder'
sys.stdout.write(s)
PY
)
sops --encrypt --azure-kv "$kid" --input-type yaml --output-type yaml "$plain" > "$out.tmp"
mv "$out.tmp" "$out"
[ "$(sops filestatus "$out")" = '{"encrypted":true}' ] || { rm -f "$out"; echo "encryption failed" >&2; exit 1; }
echo "Created $out (encrypted with $kid)"
