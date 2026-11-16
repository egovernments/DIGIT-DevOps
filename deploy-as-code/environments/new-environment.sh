#!/usr/bin/env bash
# Create a new DIGIT environment folder from _template with its OWN keys and secrets.
#
#   deploy-as-code/environments/new-environment.sh <env> <age-public-key> [db-admin-user]
#
# - <env>: environment name (folder, AKS cluster and GitHub Environment name)
# - <age-public-key>: the owning team's age public key (age1...). Generate with
#     age-keygen -o ~/.config/sops/age/<env>.txt
#   and store the private key (AGE-SECRET-KEY-1...) as secret SOPS_AGE_KEY in the
#   GitHub Environment <env>.
#
# Every secret is generated fresh here, so no two environments share a password,
# encryption key or SSH key. secrets.yaml is encrypted before the script exits;
# plaintext is never left on disk. Requires: sops, openssl, ssh-keygen, python3.
set -euo pipefail

die() { echo "error: $*" >&2; exit 1; }
[ $# -ge 2 ] || die "usage: $0 <env> <age-public-key> [db-admin-user]"
env_name=$1 age_pub=$2 db_user=${3:-digitadmin}

[[ $env_name =~ ^[a-z][a-z0-9-]{1,38}[a-z0-9]$ && $env_name != *--* ]] \
  || die "env must be 3-40 chars, lowercase letters/numbers/hyphens, start with a letter, no '--'"
[[ $age_pub =~ ^age1[0-9a-z]{58}$ ]] || die "not an age public key: $age_pub"
[[ $db_user =~ ^[a-z][a-z0-9]{2,39}$ ]] || die "db-admin-user: 3-40 lowercase letters/numbers, starting with a letter"
for c in sops openssl ssh-keygen python3; do command -v "$c" >/dev/null || die "$c not found"; done

here=$(cd "$(dirname "$0")" && pwd)
dir="$here/$env_name"
[ -e "$dir" ] && die "$dir already exists"

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
cp -R "$here/_template" "$work/env"

# random string of N chars from [A-Za-z0-9]
rnd() { python3 -c "import secrets,string,sys; a=string.ascii_letters+string.digits; print(''.join(secrets.choice(a) for _ in range(int(sys.argv[1]))))" "$1"; }

ssh-keygen -q -t ed25519 -N '' -C "git-sync@$env_name" -f "$work/git-sync" >/dev/null

# TF rule for db_password: 6-16 chars, starts with a lowercase letter, letters/numbers/@/#
python3 - "$work/env/secrets.yaml" "$work/git-sync" <<PY
import base64, secrets, string, sys, uuid
path, key = sys.argv[1], sys.argv[2]
alnum = string.ascii_letters + string.digits
r = lambda n: ''.join(secrets.choice(alnum) for _ in range(n))
ssh = open(key).read().rstrip('\n').split('\n')
vals = {
  'db_user': '$db_user',
  'db_password': secrets.choice(string.ascii_lowercase) + r(15),
  'pgadmin_password': r(24),
  'pgadmin_read_password': r(24),
  'enc_master_password': r(32),
  'enc_master_salt': r(8),
  'enc_master_iv': r(12),
  'citizen_fixed_otp': ''.join(secrets.choice(string.digits) for _ in range(6)),
  'oauth2_cookie_secret': base64.urlsafe_b64encode(secrets.token_bytes(32)).decode(),
  'elasticsearch_password': r(24),
  'kafka_kraft_cluster_id': base64.urlsafe_b64encode(uuid.uuid4().bytes).decode().rstrip('='),
  'minio_password': r(24),
  'slack_api_url': 'https://hooks.slack.com/services/not-configured',
  'slack_channel': '#not-configured',
}
s = open(path).read()
# git-sync key: YAML block scalar indented under "ssh:"
line = next(l for l in s.split('\n') if 'ssh: <git_sync_ssh_private_key>' in l)
ind = ' ' * (len(line) - len(line.lstrip()) + 4)
s = s.replace('<git_sync_ssh_private_key>', '|\n' + '\n'.join(ind + l for l in ssh))
for k, v in vals.items():
    assert s.count('<%s>' % k) == 1, k
    s = s.replace('<%s>' % k, v)
open(path, 'w').write(s)
PY

# Encrypt to this team's key only. The recipient is recorded inside secrets.yaml, so later
# `sops secrets.yaml` edits keep using it - no per-environment .sops.yaml needed.
( cd "$work/env" && sops --encrypt --age "$age_pub" --in-place secrets.yaml )
[ "$(sops filestatus "$work/env/secrets.yaml")" = '{"encrypted":true}' ] || die "encryption failed"

mv "$work/env" "$dir"
cat <<MSG
Created $dir (secrets.yaml is SOPS-encrypted to $age_pub)

Next:
 1. Edit $env_name/env.yaml - the only file you change (domain, chart repo, Azure names, overrides).
 2. GitHub -> Settings -> Environments -> New environment "$env_name", add secrets:
      SOPS_AGE_KEY  (the AGE-SECRET-KEY-1... line of your age key file)
      ARM_CLIENT_ID, ARM_CLIENT_SECRET, ARM_TENANT_ID, ARM_SUBSCRIPTION_ID
 3. Add this git-sync deploy key (read-only) to your MDMS/config repo:
      $(cat "$work/git-sync.pub")
 4. Edit secrets later with:  sops $dir/secrets.yaml
 5. Commit the folder and run the "DIGIT-Install workflow (Azure)" with environment=$env_name.
MSG
