#!/usr/bin/env bash
# Merge the team's own credentials (GitHub secret DIGIT_SECRETS) into digit-secrets.yaml.
#
#   DIGIT_USER_SECRETS="<yaml>" merge-user-secrets.sh <digit-secrets.yaml>
#
# The team never encrypts anything: this script decrypts the file with the workflow's Azure
# login, merges, and encrypts it again with the SAME Key Vault key (read from the file's own
# SOPS metadata). It only rewrites the file when a value really changed.
#
# DIGIT_SECRETS format (YAML, no "secrets:" wrapper needed):
#   notification:                  # any key that already exists in digit-secrets.yaml
#     smsUsername: my-user
#   dockerConfigJson: '{"auths":{...}}'    # optional: private image registry
#   extra:                         # optional: any other Kubernetes Secrets
#     git-ssh-key:                 #   Secret name
#       namespace: [egov]          #   optional, default = the core namespace
#       ssh-privatekey: |          #   key: value pairs
#         -----BEGIN OPENSSH PRIVATE KEY-----
#
# Refused (changing them breaks data that already exists): db, kafka, hmac.
# Exit 0 = merged or unchanged; prints "changed=true|false" on stdout.
set -euo pipefail
f=${1:?digit-secrets.yaml}
err() { echo "::error::DIGIT_SECRETS: $*" >&2; exit 1; }
[ -n "${DIGIT_USER_SECRETS:-}" ] || { echo "changed=false"; exit 0; }
[ -f "$f" ] || err "$f does not exist yet (run install first)."

work=$(mktemp -d); trap 'rm -rf "$work"' EXIT
( umask 077
  printf '%s\n' "$DIGIT_USER_SECRETS" > "$work/user.yaml"
  sops -d "$f" > "$work/current.yaml" )

yq -e 'type == "!!map"' "$work/user.yaml" >/dev/null 2>&1 \
  || err "is not valid YAML. Check the spaces at the start of each line (see ONE-CLICK-AZURE.md)."
# Accept an optional top-level "secrets:" wrapper.
if [ "$(yq -r '(keys | length) == 1 and has("secrets")' "$work/user.yaml")" = true ]; then
  yq -i '.secrets' "$work/user.yaml"
fi

# Mask every value line before anything else can print it.
if [ -n "${GITHUB_ACTIONS:-}" ]; then
  yq -r '.. | select(tag == "!!str" or tag == "!!int" or tag == "!!bool")' "$work/user.yaml" |
    while IFS= read -r line; do [ -n "$line" ] && echo "::add-mask::$line"; done
fi

blocked=$(yq -r 'keys | .[] | select(. == "db" or . == "kafka" or . == "hmac")' "$work/user.yaml")
[ -z "$blocked" ] || err "these cannot be changed, it would break existing data: $(echo "$blocked" | tr '\n' ' ')"

# Every other path must already exist in digit-secrets.yaml (catches typos), except the
# free-form extra.* and dockerConfigJson.
unknown=$(yq -r 'del(.extra) | del(.dockerConfigJson) | .. | select(tag != "!!map") | path | join(".")' "$work/user.yaml" |
  while IFS= read -r p; do
    [ "$(yq -r ".secrets.$p | tag" "$work/current.yaml" 2>/dev/null)" = "!!null" ] && echo "$p"
  done || true)
[ -z "$unknown" ] || err "unknown keys (typo?): $(echo "$unknown" | tr '\n' ' '). Allowed: the keys in deploy-as-code/helm/secrets.template.yaml, dockerConfigJson and extra."

# extra.<name> must be a map of plain values (namespace: list).
yq -e '[(.extra // {})[] | type == "!!map"] | all' "$work/user.yaml" >/dev/null 2>&1 \
  || err "every entry under extra: must be a Secret name with key: value lines under it."

# shellcheck disable=SC2016  # $i is a yq variable
( umask 077
  yq eval-all '. as $i ireduce ({}; . * $i)' "$work/current.yaml" <(yq '{"secrets": .}' "$work/user.yaml") > "$work/merged.yaml" )
if [ "$(yq -o=json -I0 . "$work/current.yaml")" = "$(yq -o=json -I0 . "$work/merged.yaml")" ]; then
  echo "changed=false"; exit 0
fi

# Re-encrypt with the same Key Vault key the file is already locked with.
kid=$(yq -r '.sops.azure_kv[0] | .vault_url + "/keys/" + .name + "/" + .version' "$f")
[[ $kid == https://*.vault.azure.net/keys/* ]] || err "$f is not locked with an Azure Key Vault key."
( umask 077; sops --encrypt --azure-kv "$kid" "$work/merged.yaml" > "$work/out.yaml" )
mv "$work/out.yaml" "$f"
echo "changed=true"
