#!/usr/bin/env bash
# install.sh — one-command orchestrator: runs phases 01–07 in order.
# Thin wrapper over the numbered scripts (each stays independently runnable);
# gathers inputs once, prompts for anything missing, stops on the first
# failure with the exact command to resume from.
#
# Usage:
#   ./install.sh --key <ssh-key> --domain <domain> --digit3 <path> \
#                --shape single-container|domain-bundles|per-service \
#                --tenant "<name>" --email <admin-email> [--vm-user azureuser]
#
# Any flag omitted is prompted for interactively. Non-interactive runs must
# pass them all. Re-running is safe — every phase is idempotent.
source "$(dirname "$0")/lib.sh"

KEY="" DOM="" VMUSER="" DIGIT3="" SHAPE="" TENANT="" EMAIL=""
while [ $# -gt 0 ]; do
  case "$1" in
    --key)     KEY="$2"; shift 2 ;;
    --domain)  DOM="$2"; shift 2 ;;
    --vm-user) VMUSER="$2"; shift 2 ;;
    --digit3)  DIGIT3="$2"; shift 2 ;;
    --shape)   SHAPE="$2"; shift 2 ;;
    --tenant)  TENANT="$2"; shift 2 ;;
    --email)   EMAIL="$2"; shift 2 ;;
    *) die "unknown option: $1 (see the header of $0 for usage)" ;;
  esac
done

ask() { # var-name prompt [default]
  local cur; eval "cur=\${$1}"
  [ -n "$cur" ] && return 0
  [ -t 0 ] || die "missing --${1,,} and not a terminal — pass it as a flag"
  local ans; read -r -p "$2${3:+ [$3]}: " ans
  eval "$1=\"\${ans:-$3}\""
  eval "[ -n \"\${$1}\" ]" || die "$1 is required"
}

echo "== DIGIT 3 install — all phases 01-07 =="
ask KEY    "ssh private-key path"
ask DOM    "VM domain (hostname only)"
if [ -z "$SHAPE" ] && [ -t 0 ]; then
  echo "deployment shape (deploy ONE — they share ingress paths):"
  echo "  1) single-container  — all 16 services in one JVM (~0.5 GB)  [recommended]"
  echo "  2) domain-bundles    — 4 JVMs: identity/notification/billing/admin"
  echo "  3) per-service       — every service its own pod (16 pods)"
  read -r -p "choice [1]: " c
  case "${c:-1}" in 1) SHAPE=single-container ;; 2) SHAPE=domain-bundles ;; 3) SHAPE=per-service ;; *) die "invalid choice '$c'" ;; esac
fi
[ -n "$SHAPE" ] || die "missing --shape"
shape_helmfile "$SHAPE" >/dev/null   # validate
ask DIGIT3 "path to the digit3 repo checkout"
ask TENANT "tenant name to seed"      "Demo Tenant"
ask EMAIL  "tenant admin email"       "admin@example.org"
VMUSER="${VMUSER:-azureuser}"

[ -f "$KEY" ]    || die "ssh key not found: $KEY"
[ -d "$DIGIT3" ] || die "digit3 path not found: $DIGIT3"
DIGIT3="$(cd "$DIGIT3" && pwd)"

echo
note "plan: shape=$SHAPE  domain=$DOM  digit3=$DIGIT3  tenant='$TENANT' <$EMAIL>"
echo

HERE="$SCRIPT_DIR"
run() { # phase-label command...
  echo; note "── phase: $1 ──"
  if ! "${@:2}"; then
    die "phase '$1' failed. Fix it (see INSTALL.md gotchas), then resume with:
    ${*:2}
  Everything is idempotent — earlier phases will no-op on the next run."
  fi
}

run "01 cluster"  "$HERE/01-cluster.sh" "$KEY" "$DOM" "$VMUSER"
run "02 secrets"  "$HERE/02-secrets.sh"
run "03 backbone" "$HERE/03-backbone.sh"
run "04 vault"    "$HERE/04-vault.sh"
run "05 images"   "$HERE/05-build.sh"  --shape "$SHAPE" "$DIGIT3"
run "06 deploy"   "$HERE/06-deploy.sh" --shape "$SHAPE" "$DIGIT3"
run "07 seed"     "$HERE/07-seed.sh"   "$TENANT" "$EMAIL" --verify

echo
note "INSTALL COMPLETE — shape '$SHAPE' deployed and verified."
echo "  kubectl:  export KUBECONFIG=~/modulith-kubeconfig.yaml"
echo "  API token for a tenant user:  ./08-token.sh <TENANT-CODE> <email>"
echo "  back up ~/.config/sops/age/keys.txt — it is the only key to the secrets"
