#!/usr/bin/env bash
# 07 — seed a tenant: account create (Keycloak realm + tenant-migration event)
# and the tenant's `individual` idgen template. With --verify, also proves the
# Vault PII pipeline end to end (INSTALL.md §1.8 Verify).
# Usage: ./07-seed.sh <tenant-name> <email> [phone-E164] [--verify]
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel

VERIFY=false
ARGS=()
for a in "$@"; do [ "$a" = "--verify" ] && VERIFY=true || ARGS+=("$a"); done
[ ${#ARGS[@]} -ge 2 ] || die "usage: $0 <tenant-name> <email> [phone-E164] [--verify]"
NAME="${ARGS[0]}" EMAIL="${ARGS[1]}" PHONE="${ARGS[2]:-+919999999999}"

# Endpoints depend on the deployed shape (06-deploy.sh persisted it in .env).
SHAPE="$(current_shape)"
case "$SHAPE" in
  single-container) ACC_SVC=dev-bundle;      IDG_SVC=dev-bundle;   IND_SVC=dev-bundle;      APP_DB=bundle_db ;;
  domain-bundles)   ACC_SVC=identity-bundle; IDG_SVC=admin-bundle; IND_SVC=identity-bundle; APP_DB=bundle_db ;;
  per-service)      ACC_SVC=account;    IDG_SVC=idgen;   IND_SVC=individual; APP_DB=postgres ;;
  *) die "unknown shape '$SHAPE' in .env" ;;
esac
svc_ip() { kubectl get svc "$1" -n egov -o jsonpath='{.spec.clusterIP}'; }
ACC_IP=$(svc_ip "$ACC_SVC"); IDG_IP=$(svc_ip "$IDG_SVC"); IND_IP=$(svc_ip "$IND_SVC")
[ -n "$ACC_IP" ] || die "$ACC_SVC service not found — run 06-deploy.sh first"
note "shape: $SHAPE (account=$ACC_SVC, idgen=$IDG_SVC, individual=$IND_SVC, db=$APP_DB)"

# Readiness pre-check: the API calls below run over ssh+curl, so an unreachable
# service would surface only as a bare non-zero curl (and set -e exits with no
# message). Fail loudly and specifically instead — pods that back these
# services must be Running/Ready before we POST anything.
check_ready() { # deploy-name
  local d="$1" ready
  ready=$(kubectl get deploy "$d" -n egov -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  if [ "${ready:-0}" -lt 1 ] 2>/dev/null; then
    local pod state
    pod=$(kubectl get pods -n egov -l "app=$d" -o jsonpath='{.items[-1:].metadata.name}' 2>/dev/null)
    state=$(kubectl get pods -n egov -l "app=$d" -o jsonpath='{.items[-1:].status.containerStatuses[0].state}' 2>/dev/null)
    die "service '$d' has no ready pod (state: ${state:-unknown}). Check: kubectl logs -n egov $pod
  A common cause is a stale vault-approle secret ('invalid role or secret ID' → CrashLoopBackOff): re-run ./04-vault.sh, then kubectl rollout restart deploy/$d -n egov"
  fi
}
for d in $(printf '%s\n' "$ACC_SVC" "$IDG_SVC" "$IND_SVC" | sort -u); do check_ready "$d"; done
echo "    services ready"

note "creating tenant '$NAME' (all calls run on the VM — port-forward is unreliable)"
# The backend user is created with the email as username and this password —
# generated here (16 chars, JSON-safe) and printed ONCE at the end. Without it
# the server generates one that is never delivered (SMTP is a placeholder).
ADMIN_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-16)
RESP=$(vm_curl "-X POST http://$ACC_IP:8080/account/v3/tenants -H 'Content-Type: application/json' -d '{\"name\":\"$NAME\",\"email\":\"$EMAIL\",\"phone\":\"$PHONE\",\"password\":\"$ADMIN_PASS\"}'")
CODE=$(printf '%s' "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('code',''))" 2>/dev/null || true)
FRESH_TENANT=true
if [ -z "$CODE" ]; then
  # already exists? look it up by email before giving up
  CODE=$(vm_curl "'http://$ACC_IP:8080/account/v3/tenants?email=$EMAIL'" | \
    python3 -c "import sys,json;ts=json.load(sys.stdin).get('tenants') or [];print(ts[0]['code'] if ts else '')" 2>/dev/null || true)
  [ -n "$CODE" ] && { echo "    tenant already exists (admin password unchanged)"; FRESH_TENANT=false; ADMIN_PASS=""; } \
    || die "tenant create failed: $RESP"
fi
echo "    tenant code: $CODE"

note "waiting for the tenant-migration event to build the '$CODE' schema"
WAITED=0
until psql_exec -d "$APP_DB" -tAc "SELECT 1 FROM information_schema.schemata WHERE schema_name='$CODE'" | grep -q 1; do
  sleep 3; WAITED=$((WAITED + 3))
  [ "$WAITED" -ge 120 ] && die "schema $CODE not created after ${WAITED}s — check the bundle logs for [tenant-migration]"
done
echo "    schema ready"

note "registering the tenant's 'individual' idgen template"
TRESP=$(vm_curl "-X POST http://$IDG_IP:8080/idgen/v3/template -H 'Content-Type: application/json' -H 'X-Tenant-ID: $CODE' -H 'X-User-ID: seed-script' -d '{\"templateCode\":\"individual\",\"config\":{\"template\":\"IND-{DATE:yyyy}-{SEQ}\",\"sequence\":{\"scope\":\"GLOBAL\",\"start\":1,\"padding\":{\"length\":6,\"char\":\"0\"}}}}'")
printf '%s' "$TRESP" | grep -q '"templateCode":"individual"' && echo "    template registered" || \
  { printf '%s' "$TRESP" | grep -qi "exists" && echo "    template already exists" || die "template create failed: $TRESP"; }

print_credentials() {
  if [ -n "$ADMIN_PASS" ]; then
    echo
    echo "  tenant admin login (shown ONCE — store it now, e.g. in a password manager):"
    echo "    username: $EMAIL"
    echo "    password: $ADMIN_PASS"
  fi
}

if ! $VERIFY; then
  note "done — tenant $CODE is ready"
  print_credentials
  exit 0
fi

note "verify: creating a test individual with a mobile number"
MOBILE="9$(printf '%09d' $((RANDOM * RANDOM % 1000000000)))"
IRESP=$(vm_curl "-X POST http://$IND_IP:8080/individual/v3/individuals -H 'Content-Type: application/json' -H 'X-Tenant-ID: $CODE' -H 'X-User-ID: seed-script' -d '{\"givenName\":\"Seed\",\"familyName\":\"Verify\",\"mobileNumber\":\"$MOBILE\",\"gender\":\"OTHER\"}'")
IND_ID=$(printf '%s' "$IRESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('individualId',''))" 2>/dev/null || true)
[ -n "$IND_ID" ] || die "individual create failed: $IRESP"

P1=FAIL; printf '%s' "$IRESP" | grep -q "\"mobileNumber\":\"$MOBILE\"" && P1=PASS
ROW=$(psql_exec -d "$APP_DB" -tAc "SELECT mobilenumber||'|'||hashedmobilenumber FROM \"$CODE\".individual_v3 WHERE individualid='$IND_ID'")
P2=FAIL; printf '%s' "$ROW" | grep -q "^vault:v1:" && ! printf '%s' "$ROW" | grep -q "$MOBILE" && P2=PASS
P3=FAIL; vault_exec 'vault list -format=json transit/keys' | grep -q "\"$CODE\"" && P3=PASS

echo
echo "  API returns plaintext mobile           : $P1  ($IND_ID)"
echo "  DB stores vault:v1 ciphertext + HMAC   : $P2"
echo "  per-tenant transit key exists in Vault : $P3"
[ "$P1$P2$P3" = "PASSPASSPASS" ] && note "verification PASSED" || die "verification FAILED — see the gotchas table in INSTALL.md"
print_credentials
