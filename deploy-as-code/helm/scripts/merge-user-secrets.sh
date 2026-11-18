#!/usr/bin/env bash
# Merge the team's own credentials (GitHub secret DIGIT_SECRETS) into <env>-secrets.yaml.
#
#   DIGIT_USER_SECRETS="<yaml>" merge-user-secrets.sh <env>-secrets.yaml <secrets template>
#
# The team never encrypts anything: this script decrypts the file with the workflow's Azure
# login, merges, and encrypts it again with the SAME Key Vault key (read from the file's own
# SOPS metadata). It only rewrites the file when a value really changed. It also fills in
# placeholders that exist in the template but not yet in the file (added in a newer version
# of this repo) with fresh random values, so older environments keep working.
#
# DIGIT_SECRETS uses the same layout as the secrets file, for example:
#   cluster-configs:
#     secrets:
#       egov-notification-sms: {username: my-user, password: my-pass}
#       docker-registry-secret: {dockerconfigjson: '{"auths":{...}}'}
#       git-ssh-key:                       # a NEW Secret: any new name under secrets
#         namespace: [egov]                #   optional, default [egov]
#         ssh-privatekey: |
#           -----BEGIN OPENSSH PRIVATE KEY-----
#   grafana: {adminPassword: my-pass}
#   argocd: {adminPassword: my-pass}
#
# Refused (changing them breaks data that already exists):
#   cluster-configs.secrets.db, .kafka-kraft-cluster-id, .hmac-secret
# Any other path must exist in the template (catches typos), except new Secrets.
# Prints "changed=true|false" on stdout.
set -euo pipefail
f=${1:?<env>-secrets.yaml}; tmpl=${2:?secrets template}
err() { echo "::error::DIGIT_SECRETS: $*" >&2; exit 1; }
[ -f "$f" ] || err "$f does not exist yet (run install first)."
# yq path expression for a dotted path whose keys may contain "-"
q() { printf '.["%s"]' "${1//./\"][\"}"; }

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
( umask 077
  if [ -n "${DIGIT_USER_SECRETS:-}" ]; then printf '%s\n' "$DIGIT_USER_SECRETS"; else echo '{}'; fi > "$work/user.yaml"
  sops -d "$f" > "$work/current.yaml"
  cp "$work/current.yaml" "$work/before.yaml" )

# 1. Template placeholders missing from the file (newer repo version) -> fresh random value.
yq -r '.. | select(tag == "!!str" and test("^<[a-z_]+>$")) | path | join(".")' "$tmpl" |
  while IFS= read -r p; do
    [ "$(yq -r "$(q "$p") | tag" "$work/current.yaml")" = "!!null" ] || continue
    v=$(python3 -c "import secrets,string; a=string.ascii_letters+string.digits; print(''.join(secrets.choice(a) for _ in range(24)))")
    ( umask 077; V="$v" yq -i "$(q "$p") = strenv(V)" "$work/current.yaml" )
    echo "added missing secret $p" >&2
  done

yq -e 'type == "!!map"' "$work/user.yaml" >/dev/null 2>&1 \
  || err "is not valid YAML. Check the spaces at the start of each line (see ONE-CLICK-AZURE.md)."

# Mask every value line before anything else can print it.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  yq -r '.. | select(tag == "!!str" or tag == "!!int" or tag == "!!bool")' "$work/user.yaml" |
    while IFS= read -r line; do [ -n "$line" ] && echo "::add-mask::$line"; done
fi

blocked=$(yq -r '(.["cluster-configs"].secrets // {}) | keys | .[] | select(. == "db" or . == "kafka-kraft-cluster-id" or . == "hmac-secret")' "$work/user.yaml")
[ -z "$blocked" ] || err "these cannot be changed, it would break existing data: cluster-configs.secrets.$(echo "$blocked" | paste -sd, -)"

# New Secrets (a name under cluster-configs.secrets that the template does not have):
# must be a map; namespace defaults to [egov].
new=""
while IFS= read -r s; do
  [ -n "$s" ] || continue
  [ "$(yq -r "$(q "cluster-configs.secrets.$s") | tag" "$tmpl")" = "!!null" ] || continue
  [ "$(yq -r "$(q "cluster-configs.secrets.$s") | tag" "$work/user.yaml")" = "!!map" ] \
    || err "cluster-configs.secrets.$s must be a Secret: key: value lines under it."
  yq -i "$(q "cluster-configs.secrets.$s").namespace = ($(q "cluster-configs.secrets.$s").namespace // [\"egov\"])" "$work/user.yaml"
  new="$new $s"
done < <(yq -r '(.["cluster-configs"].secrets // {}) | keys | .[]' "$work/user.yaml")

# Every other path must exist in the template (catches typos).
unknown=""
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case " $new " in *" $(cut -d. -f3 <<< "$p") "*) [[ $p == cluster-configs.secrets.* ]] && continue ;; esac
  [ "$(yq -r "$(q "$p") | tag" "$tmpl")" = "!!null" ] && unknown="$unknown $p"
done < <(yq -r '.. | select(tag != "!!map" and tag != "!!seq") | path | join(".")' "$work/user.yaml")
[ -z "$unknown" ] || err "unknown keys (typo?):$unknown. Use the paths in deploy-as-code/helm/environments/digit-template-secrets.yaml, or add a new Secret under cluster-configs.secrets."

# shellcheck disable=SC2016  # $i is a yq variable
( umask 077
  yq eval-all '. as $i ireduce ({}; . * $i)' "$work/current.yaml" "$work/user.yaml" > "$work/merged.yaml" )
if [ "$(yq -o=json -I0 . "$work/before.yaml")" = "$(yq -o=json -I0 . "$work/merged.yaml")" ]; then
  echo "changed=false"; exit 0
fi

# Re-encrypt with the same Key Vault key the file is already locked with.
kid=$(yq -r '.sops.azure_kv[0] | .vault_url + "/keys/" + .name + "/" + .version' "$f")
[[ $kid == https://*.vault.azure.net/keys/* ]] || err "$f is not locked with an Azure Key Vault key."
( umask 077; sops --encrypt --azure-kv "$kid" --input-type yaml --output-type yaml "$work/merged.yaml" > "$work/out.yaml" )
mv "$work/out.yaml" "$f"
echo "changed=true"
