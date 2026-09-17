#!/usr/bin/env bash
# Seed a tenant + the runtime lookups every fresh environment needs, on
# whichever shape 06-deploy.sh last deployed (scripts/.last-shape):
#   - tenant (Keycloak realm + per-tenant schema via the tenant-migration event)
#   - otp configs for login/registration (idempotent; account also seeds them
#     itself because the create carries X-User-ID)
#   - idgen templates: individual, registryId, BillNumber, ReceiptNumber, TxnID
#   - the sms-otp-login notification template (the OTP SMS dispatch renders it)
# --verify additionally proves the Vault PII pipeline end to end.
#
#   ./07-seed.sh <tenant-name> <email> [phone-E164] [--verify]
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel
VERIFY=false
ARGS=()
for a in "$@"; do [ "$a" = "--verify" ] && VERIFY=true || ARGS+=("$a"); done
[ ${#ARGS[@]} -ge 2 ] || die "usage: $0 <tenant-name> <email> [phone-E164] [--verify]"
NAME="${ARGS[0]}" EMAIL="${ARGS[1]}" PHONE="${ARGS[2]:-+919999999999}"

SHAPE=$(cat "$SCRIPT_DIR/.last-shape" 2>/dev/null || true)
[ -n "$SHAPE" ] || die "scripts/.last-shape missing — run 06-deploy.sh first"
svc_ip() { kubectl get svc "$1" -n egov -o jsonpath='{.spec.clusterIP}'; }
case "$SHAPE" in
  services)     ACCOUNT=$(svc_ip account); IDGEN=$(svc_ip idgen)
                INDIVIDUAL=$(svc_ip individual); NOTIF=$(svc_ip notification); OTP=$(svc_ip otp) ;;
  dev-bundle)   ACCOUNT=$(svc_ip dev-bundle); IDGEN=$ACCOUNT; INDIVIDUAL=$ACCOUNT; NOTIF=$ACCOUNT; OTP=$ACCOUNT ;;
  domain-split) ACCOUNT=$(svc_ip identity-bundle); INDIVIDUAL=$ACCOUNT; OTP=$ACCOUNT
                IDGEN=$(svc_ip admin-bundle); NOTIF=$(svc_ip notification-bundle) ;;
  *) die "unknown shape in scripts/.last-shape: $SHAPE" ;;
esac
[ -n "$ACCOUNT" ] || die "account-hosting service not found — is shape '$SHAPE' deployed?"
H_JSON="-H 'Content-Type: application/json'"

note "creating tenant '$NAME' on shape '$SHAPE' (all calls run on the VM)"
RESP=$(vm_curl "-X POST http://$ACCOUNT:8080/account/v3/tenants $H_JSON -H 'X-User-ID: seed-script' -d '{\"name\":\"$NAME\",\"email\":\"$EMAIL\",\"phone\":\"$PHONE\"}'")
CODE=$(printf '%s' "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('code',''))" 2>/dev/null || true)
if [ -z "$CODE" ]; then
  CODE=$(vm_curl "'http://$ACCOUNT:8080/account/v3/tenants?email=$EMAIL'" | \
    python3 -c "import sys,json;ts=json.load(sys.stdin).get('tenants') or [];print(ts[0]['code'] if ts else '')" 2>/dev/null || true)
  [ -n "$CODE" ] && echo "    tenant already exists" || die "tenant create failed: $RESP"
fi
echo "    tenant code: $CODE"

note "waiting for the tenant-migration event to build the '$CODE' schema"
WAITED=0
until psql_exec -tAc "SELECT 1 FROM information_schema.schemata WHERE schema_name='$CODE'" | grep -q 1; do
  sleep 3; WAITED=$((WAITED + 3))
  [ "$WAITED" -ge 180 ] && die "schema $CODE not created after ${WAITED}s — check [tenant-migration] in the consumer logs"
done
echo "    schema ready"

hdr() { echo "-H 'X-Tenant-ID: $CODE' -H 'X-User-ID: seed-script'"; }
seed() { # label url json ok-marker
  local out; out=$(vm_curl "-X POST $2 $H_JSON $(hdr) -d '$3'")
  if printf '%s' "$out" | grep -q "$4"; then echo "    $1: created"
  elif printf '%s' "$out" | grep -qiE "exists|conflict|409"; then echo "    $1: already present"
  else die "$1 failed: $out"; fi
}
note "otp configs (login, registration)"
for p in login registration; do
  seed "otp config $p" "http://$OTP:8080/otp/v3/config" "{\"purpose\":\"$p\"}" '"purpose"'
done
note "idgen templates"
for t in individual registryId BillNumber ReceiptNumber TxnID; do
  seed "idgen $t" "http://$IDGEN:8080/idgen/v3/template" \
    "{\"templateCode\":\"$t\",\"config\":{\"template\":\"${t:0:3}-{DATE:yyyy}-{SEQ}\",\"sequence\":{\"scope\":\"GLOBAL\",\"start\":1,\"padding\":{\"length\":6,\"char\":\"0\"}}}}" '"templateCode"'
done
note "sms-otp-login notification template"
seed "sms-otp-login" "http://$NOTIF:8080/notification/v3/template" \
  '{"templateId":"sms-otp-login","type":"SMS","content":"Your OTP is {{ .otp }}. Valid 5 minutes."}' '"templateId"'

if ! $VERIFY; then
  note "done — tenant $CODE is seeded and ready"
  exit 0
fi

note "verify: creating a test individual with a mobile number"
MOBILE="9$(printf '%09d' $((RANDOM * RANDOM % 1000000000)))"
IRESP=$(vm_curl "-X POST http://$INDIVIDUAL:8080/individual/v3/individuals $H_JSON $(hdr) -d '{\"givenName\":\"Seed\",\"familyName\":\"Verify\",\"mobileNumber\":\"$MOBILE\",\"gender\":\"OTHER\"}'")
IND_ID=$(printf '%s' "$IRESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('individualId',''))" 2>/dev/null || true)
[ -n "$IND_ID" ] || die "individual create failed: $IRESP"
P1=FAIL; printf '%s' "$IRESP" | grep -q "\"mobileNumber\":\"$MOBILE\"" && P1=PASS
ROW=$(psql_exec -tAc "SELECT mobilenumber||'|'||hashedmobilenumber FROM \"$CODE\".individual_v3 WHERE individualid='$IND_ID'")
P2=FAIL; printf '%s' "$ROW" | grep -q "^vault:v1:" && ! printf '%s' "$ROW" | grep -q "$MOBILE" && P2=PASS
P3=FAIL; vault_exec 'vault list -format=json transit/keys' | grep -q "\"$CODE\"" && P3=PASS
echo
echo "  API returns plaintext mobile           : $P1  ($IND_ID)"
echo "  DB stores vault:v1 ciphertext + HMAC   : $P2"
echo "  per-tenant transit key exists in Vault : $P3"
[ "$P1$P2$P3" = "PASSPASSPASS" ] && note "verification PASSED" || die "verification FAILED — see the gotchas table in INSTALL.md"
