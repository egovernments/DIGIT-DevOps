#!/usr/bin/env bash
# ONE command from a provisioned VM to a deployed, seeded, verified DIGIT 3 —
# a thin orchestrator over the idempotent phase scripts (01→07). Adapted from
# modulith-final's install.sh onto this branch's shape/tag model: shapes are
# services | dev-bundle | domain-split (modulith-final's names accepted as
# synonyms), images come from the published Actions builds via --tag (verified
# against Docker Hub before deploying), and no tracked file is mutated.
#
#   ./install.sh --key <ssh-key> --domain <domain> --digit3 <path> \
#                --shape services|dev-bundle|domain-split --tag modulith-<sha> \
#                --tenant "Name" --email admin@org [--vm-user azureuser] [--skip-vault]
#
# Run without flags on a terminal and it prompts. On failure it stops with the
# exact resume command; every phase converges to a no-op when re-run.
source "$(dirname "$0")/lib.sh"

KEY="" DOM="" VMUSER="" DIGIT3="" SHAPE="" TAG="" TENANT="" EMAIL="" SKIP_VAULT=false
while [ $# -gt 0 ]; do
  case "$1" in
    --key)        KEY="$2"; shift 2 ;;
    --domain)     DOM="$2"; shift 2 ;;
    --vm-user)    VMUSER="$2"; shift 2 ;;
    --digit3)     DIGIT3="$2"; shift 2 ;;
    --shape)      SHAPE="$2"; shift 2 ;;
    --tag)        TAG="$2"; shift 2 ;;
    --tenant)     TENANT="$2"; shift 2 ;;
    --email)      EMAIL="$2"; shift 2 ;;
    --skip-vault) SKIP_VAULT=true; shift ;;
    *) die "unknown option: $1 (see the header of $0)" ;;
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
ask KEY "ssh private-key path"
ask DOM "VM domain (hostname only)"
if [ -z "$SHAPE" ] && [ -t 0 ]; then
  echo "deployment shape (deploy ONE — they share ingress paths and kong prefixes):"
  echo "  1) dev-bundle    — all 16 services in one JVM (~0.5 GB)  [recommended]"
  echo "  2) domain-split  — 4 JVMs: identity/notification/billing/admin"
  echo "  3) services      — every service its own pod (16 pods)"
  read -r -p "choice [1]: " c
  case "${c:-1}" in 1) SHAPE=dev-bundle ;; 2) SHAPE=domain-split ;; 3) SHAPE=services ;; *) die "invalid choice '$c'" ;;
  esac
fi
# accept modulith-final's shape names as synonyms
case "$SHAPE" in
  single-container) SHAPE=dev-bundle ;;
  domain-bundles)   SHAPE=domain-split ;;
  per-service)      SHAPE=services ;;
esac
case "$SHAPE" in services|dev-bundle|domain-split) ;; *) die "unknown shape '$SHAPE'" ;; esac
ask DIGIT3 "path to the digit3 repo checkout"
ask TAG    "image tag (published Actions build, modulith-<sha>)"
ask TENANT "tenant name to seed"  "Demo Tenant"
ask EMAIL  "tenant admin email"   "admin@example.org"
VMUSER="${VMUSER:-azureuser}"
[ -f "$KEY" ]    || die "ssh key not found: $KEY"
[ -d "$DIGIT3" ] || die "digit3 path not found: $DIGIT3"
DIGIT3="$(cd "$DIGIT3" && pwd)"

# ── preflight: every image this shape deploys must exist on Docker Hub ────────
hub_has() { curl -sfm 10 "https://hub.docker.com/v2/repositories/egovio/$1/tags/$2" >/dev/null 2>&1; }
case "$SHAPE" in
  services)     IMAGES="idgen template-config billing apportion url-shortener pg-service otp notification employee individual workflow registry filestore localization account boundary" ;;
  dev-bundle)   IMAGES="dev-bundle" ;;
  domain-split) IMAGES="identity-bundle notification-bundle billing-bundle admin-bundle" ;;
esac
note "preflight: verifying egovio images at :$TAG on Docker Hub"
MISSING=""
for i in $IMAGES; do
  for r in "$i" "$i-db"; do hub_has "$r" "$TAG" || MISSING="$MISSING $r"; done
done
[ -z "$MISSING" ] || die "not on the hub at :$TAG:$MISSING — pick a published tag (dispatch the Actions builds first)"
echo "    all $(echo $IMAGES | wc -w) image pairs published"

echo
note "plan: shape=$SHAPE  tag=$TAG  domain=$DOM  digit3=$DIGIT3  vault=$($SKIP_VAULT && echo skip || echo yes)  tenant='$TENANT' <$EMAIL>"
echo

HERE="$SCRIPT_DIR"
run() { # phase-label command...
  echo; note "── phase: $1 ──"
  if ! "${@:2}"; then
    die "phase '$1' failed. Fix it (see the gotchas table in INSTALL.md), then resume with:
    ${*:2}
  Everything is idempotent — earlier phases will no-op on the next run."
  fi
}

run "01 cluster"  "$HERE/01-cluster.sh" "$KEY" "$DOM" "$VMUSER"
run "02 secrets"  "$HERE/02-secrets.sh"
run "03 backbone" "$HERE/03-backbone.sh"
if $SKIP_VAULT; then
  note "── phase: 04 vault — SKIPPED (--skip-vault; ensure the env blocks set VAULT_ENABLED=false) ──"
else
  run "04 vault"  "$HERE/04-vault.sh"
fi
run "06 deploy"   "$HERE/06-deploy.sh" "$DIGIT3" "$SHAPE" "$TAG"
if $SKIP_VAULT; then
  run "07 seed"   "$HERE/07-seed.sh" "$TENANT" "$EMAIL"
else
  run "07 seed"   "$HERE/07-seed.sh" "$TENANT" "$EMAIL" --verify
fi

echo
note "INSTALL COMPLETE — shape '$SHAPE' at :$TAG deployed$($SKIP_VAULT || echo ' and Vault-verified')."
echo "  kubectl:            export KUBECONFIG=~/modulith-kubeconfig.yaml"
echo "  API token helper:   ./08-token.sh <TENANT-CODE> <email>"
echo "  back up ~/.config/sops/age/keys.txt — it is the only key to the secrets"
