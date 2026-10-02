#!/bin/bash
# LnP API test helpers — run from the DevOps digit3/scripts dir of the target VM (its .env picks the cluster).
# Tokens are minted with 08-token.sh and travel to the VM over the ssh stdin, never argv/stdout.
#   source lib-api.sh <scripts-dir> <tenant> <email> <password-capture-file>
SCRIPTS=$1; TENANT=${2:-BASETENANT}; EMAIL=$3; PWFILE=${4:-}
source "$SCRIPTS/lib.sh"; load_env; ensure_tunnel >/dev/null
set +e; trap - ERR; set +u   # lib.sh is strict; a failing check must not abort the suite
KGIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
TOKFILE=$(umask 077; mktemp "$HOME/.lnp-tok.XXXXXX")
mint() { # mint <tenant> <email> <password-file> -> token saved in $TOKFILE (file: 07-seed capture or a bare password)
  local pw; pw=$(sed -n 's/^\s*password: //p' "$3" | head -1); [ -n "$pw" ] || pw=$(cat "$3")
  "$SCRIPTS/08-token.sh" "$1" "$2" "$pw" 2>/dev/null | grep -E '^ey[A-Za-z0-9_-]+\.' | head -1 > "$TOKFILE"; unset pw
  [ -s "$TOKFILE" ] || { echo "  !! no token for $2@$1"; return 1; }
}
PASS=0; FAIL=0; REPORT=${REPORT:-/tmp/lnp-api-report.txt}
# api <METHOD> <path> [json-body] [extra curl args] -> CODE, BODY. Line 1 of stdin = token, rest = body (curl -d @-).
api() {
  local m=$1 p=$2 body=${3:-} extra=${4:-}; local out
  out=$( { cat "$TOKFILE"; printf '%s' "$body"; } | vm_ssh "read -r T; curl -s -m 90 -w '\n%{http_code}' -X $m 'http://$KGIP:8000$p' -H 'Host: $DOMAIN' -H 'X-Tenant-ID: $TENANT' -H 'X-User-Id: lnp-test' -H 'X-Client-ID: lnp-test' -H 'Content-Type: application/json' -H \"Authorization: Bearer \$T\" $extra ${body:+-d @-}")
  CODE=${out##*$'\n'}; BODY=${out%$'\n'*}; BODY=${BODY:0:60000}
}
check() { # check "<name>" <expected-codes-regex>
  if [[ "$CODE" =~ ^($2)$ ]]; then PASS=$((PASS+1)); printf "  PASS  %-62s HTTP %s\n" "$1" "$CODE" | tee -a "$REPORT"
  else FAIL=$((FAIL+1)); printf "  FAIL  %-62s HTTP %s  %s\n" "$1" "$CODE" "${BODY:0:160}" | tee -a "$REPORT"; fi
}
jq_() { printf '%s' "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null || true; }
summary() { echo; echo "  API checks: PASS=$PASS FAIL=$FAIL" | tee -a "$REPORT"; rm -f "$TOKFILE"; }
