#!/usr/bin/env bash
# What does HEAD need for environment <env>, compared with what is running in Azure?
#
#   one-click-changes.sh <env> <last-infra-commit> <last-deploy-commit> [<last-products-commit>]
#
# The commits are read from the environment's resource-group tags (digit-infra-sha,
# digit-deploy-sha, digit-products-sha), written after every successful Infra / Deploy /
# Products job. Prints "infra=", "deploy=" and "products=" true|false (reasons go to stderr).
#   infra    : Terraform code changed, or location / terraform_* in one-click/input.yaml changed
#   deploy   : the rest of input.yaml (domain, email, helmfiles_ref, ...), one-click/<env>.yaml
#              except its products block, or one-click/<env>-secrets.yaml changed; also a
#              product's namespace / shared-secrets / enabled (cluster-configs makes the namespace)
#   products : the products block of one-click/<env>.yaml, or the deploy part of input.yaml
#              (domain, helmfiles_ref, ...: products get them too) changed
# An unknown or unreachable commit (first run, force-push) means "run it" - always safe.
set -euo pipefail
env=${1:?environment}
INPUT=one-click/input.yaml
ENVF="one-click/${env}.yaml"
INFRA_RE='^infra-as-code/terraform/(azure/|modules/[^/]+/azure/|scripts/init\.go$)'
DEPLOY_RE="^one-click/${env}-secrets\\.yaml\$"
NONE_RE='^$'
INFRA_CFG='with_entries(select(.key == "location" or (.key | test("^terraform_"))))'
DEPLOY_CFG='with_entries(select((.key == "location" or (.key | test("^terraform_"))) | not))'
# the part of the products block the platform acts on (namespaces + shared Secrets)
PRODUCT_NS='[(.products // {}) | to_entries[] | select(.value.enabled != false and (.value.namespace // "egov") != "egov") | {"n": .key, "ns": .value.namespace, "s": (.value["shared-secrets"] // [])}]'

have() { # make sure commit $1 is available locally (shallow fetch of just that commit)
  [ -n "$1" ] || return 1
  git cat-file -e "$1^{commit}" 2>/dev/null && return 0
  git fetch -q --no-tags --depth=1 origin "$1" 2>/dev/null && git cat-file -e "$1^{commit}" 2>/dev/null
}
# a YAML file at a commit, reduced by a yq expression, as one line of JSON
part() { git show "$1:$2" 2>/dev/null | yq -o=json -I0 "$3" 2>/dev/null || echo "<none>"; }

decide() { # <what> <last-commit> <path-regex> <file>|<yq-expr> ...
  local what=$1 last=$2 re=$3 files f e
  shift 3
  if ! have "$last"; then
    echo "$what: last applied commit unknown (${last:-none}) - running" >&2; echo true; return
  fi
  files=$(git diff --name-only "$last" HEAD | grep -E "$re" || true)
  if [ -n "$files" ]; then
    echo "$what: files changed since ${last:0:9}:" >&2
    while read -r f; do echo "  $f" >&2; done <<< "$files"
    echo true; return
  fi
  for pair in "$@"; do
    f=${pair%%|*}; e=${pair#*|}
    if [ "$(part "$last" "$f" "$e")" != "$(part HEAD "$f" "$e")" ]; then
      echo "$what: $f changed since ${last:0:9} ($e)" >&2; echo true; return
    fi
  done
  echo "$what: nothing changed since ${last:0:9}" >&2; echo false
}

echo "infra=$(decide infra "${2:-}" "$INFRA_RE" "$INPUT|$INFRA_CFG")"
echo "deploy=$(decide deploy "${3:-}" "$DEPLOY_RE" "$INPUT|$DEPLOY_CFG" "$ENVF|del(.products)" "$ENVF|$PRODUCT_NS")"
echo "products=$(decide products "${4:-}" "$NONE_RE" "$ENVF|.products // {}" "$INPUT|$DEPLOY_CFG")"
