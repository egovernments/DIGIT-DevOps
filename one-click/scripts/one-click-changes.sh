#!/usr/bin/env bash
# What does HEAD need for environment <env>, compared with what is running in Azure?
#
#   one-click-changes.sh <env> <last-infra-commit> <last-deploy-commit>
#
# The two commits are read from the environment's resource-group tags
# (digit-infra-sha / digit-deploy-sha), written after every successful Infra / Deploy job.
# Prints "infra=true|false" and "deploy=true|false" (reasons go to stderr).
#   infra  : Terraform code changed, or location / terraform_* in one-click/input.yaml changed
#   deploy : the rest of input.yaml (domain, email, helmfiles_ref, ...),
#            one-click/<env>.yaml or one-click/<env>-secrets.yaml changed
# An unknown or unreachable commit (first run, force-push) means "run it" - always safe.
set -euo pipefail
env=${1:?environment}
INPUT=one-click/input.yaml
INFRA_RE='^infra-as-code/terraform/(azure/|modules/[^/]+/azure/|scripts/init\.go$)'
DEPLOY_RE="^one-click/${env}(-secrets)?\\.yaml\$"
INFRA_CFG='with_entries(select(.key == "location" or (.key | test("^terraform_"))))'
DEPLOY_CFG='with_entries(select((.key == "location" or (.key | test("^terraform_"))) | not))'

have() { # make sure commit $1 is available locally (shallow fetch of just that commit)
  [ -n "$1" ] || return 1
  git cat-file -e "$1^{commit}" 2>/dev/null && return 0
  git fetch -q --no-tags --depth=1 origin "$1" 2>/dev/null && git cat-file -e "$1^{commit}" 2>/dev/null
}
cfg() { git show "$1:$INPUT" 2>/dev/null | yq -o=json -I0 "$2" 2>/dev/null || echo "<none>"; }

decide() { # <what> <last-commit> <path-regex> <input.yaml-part>
  local what=$1 last=$2 files
  if ! have "$last"; then
    echo "$what: last applied commit unknown (${last:-none}) - running" >&2; echo true; return
  fi
  files=$(git diff --name-only "$last" HEAD | grep -E "$3" || true)
  if [ -n "$files" ]; then
    echo "$what: files changed since ${last:0:9}:" >&2
    while read -r f; do echo "  $f" >&2; done <<< "$files"
    echo true; return
  fi
  if [ "$(cfg "$last" "$4")" != "$(cfg HEAD "$4")" ]; then
    echo "$what: $INPUT changed since ${last:0:9}" >&2; echo true; return
  fi
  echo "$what: nothing changed since ${last:0:9}" >&2; echo false
}

echo "infra=$(decide infra "${2:-}" "$INFRA_RE" "$INFRA_CFG")"
echo "deploy=$(decide deploy "${3:-}" "$DEPLOY_RE" "$DEPLOY_CFG")"
