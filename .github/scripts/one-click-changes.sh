#!/usr/bin/env bash
# What does HEAD need, compared with what is running in Azure?
#
#   one-click-changes.sh <last-infra-commit> <last-deploy-commit>
#
# The two commits are read from the environment's resource-group tags
# (digit-infra-sha / digit-deploy-sha), written after every successful Infra / Deploy job.
# Prints "infra=true|false" and "deploy=true|false" (reasons go to stderr).
#   infra  : Terraform code changed, or terraform:/location in digit-config.yaml changed
#   deploy : helmfiles/values/defaults/Vault script changed, digit-secrets.yaml changed,
#            or any other part of digit-config.yaml changed
# An unknown or unreachable commit (first run, force-push) means "run it" - always safe.
set -euo pipefail
INFRA_RE='^infra-as-code/terraform/(azure/|modules/[^/]+/azure/|scripts/init\.go$)'
DEPLOY_RE='^(digit-secrets\.yaml$|deploy-as-code/helm/(defaults\.yaml$|digit-helmfile\.yaml\.gotmpl$|helmfiles/|values/|scripts/vault-bootstrap\.sh$|charts/monitoring/values/))'
INFRA_CFG='{"terraform": .terraform, "location": .location}'
DEPLOY_CFG='del(.terraform) | del(.location)'

have() { # make sure commit $1 is available locally (shallow fetch of just that commit)
  [ -n "$1" ] || return 1
  git cat-file -e "$1^{commit}" 2>/dev/null && return 0
  git fetch -q --no-tags --depth=1 origin "$1" 2>/dev/null && git cat-file -e "$1^{commit}" 2>/dev/null
}
cfg() { git show "$1:digit-config.yaml" 2>/dev/null | yq -o=json -I0 "$2" 2>/dev/null || echo "<none>"; }

decide() { # <what> <last-commit> <path-regex> <config-part>
  local what=$1 last=$2 files
  if ! have "$last"; then
    echo "$what: last applied commit unknown (${last:-none}) - running" >&2; echo true; return
  fi
  files=$(git diff --name-only "$last" HEAD | grep -E "$3" || true)
  if [ -n "$files" ]; then
    echo "$what: files changed since ${last:0:9}:" >&2; while read -r f; do echo "  $f" >&2; done <<< "$files"; echo true; return
  fi
  if [ "$(cfg "$last" "$4")" != "$(cfg HEAD "$4")" ]; then
    echo "$what: digit-config.yaml changed since ${last:0:9}" >&2; echo true; return
  fi
  echo "$what: nothing changed since ${last:0:9}" >&2; echo false
}

echo "infra=$(decide infra "${1:-}" "$INFRA_RE" "$INFRA_CFG")"
echo "deploy=$(decide deploy "${2:-}" "$DEPLOY_RE" "$DEPLOY_CFG")"
