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

BIP=$(kubectl get svc dev-bundle -n egov -o jsonpath='{.spec.clusterIP}')
[ -n "$BIP" ] || die "dev-bundle service not found — run 06-deploy.sh first"

note "creating tenant '$NAME' (all calls run on the VM — port-forward is unreliable)"
RESP=$(vm_curl "-X POST http://$BIP:8080/account/v3/tenants -H 'Content-Type: application/json' -d '{\"name\":\"$NAME\",\"email\":\"$EMAIL\",\"phone\":\"$PHONE\"}'")
CODE=$(printf '%s' "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('code',''))" 2>/dev/null || true)
if [ -z "$CODE" ]; then
  # already exists? look it up by email before giving up
  CODE=$(vm_curl "'http://$BIP:8080/account/v3/tenants?email=$EMAIL'" | \
    python3 -c "import sys,json;ts=json.load(sys.stdin).get('tenants') or [];print(ts[0]['code'] if ts else '')" 2>/dev/null || true)
  [ -n "$CODE" ] && echo "    tenant already exists" || die "tenant create failed: $RESP"
fi
echo "    tenant code: $CODE"

note "waiting for the tenant-migration event to build the '$CODE' schema"
WAITED=0
until psql_exec -d bundle_db -tAc "SELECT 1 FROM information_schema.schemata WHERE schema_name='$CODE'" | grep -q 1; do
  sleep 3; WAITED=$((WAITED + 3))
  [ "$WAITED" -ge 120 ] && die "schema $CODE not created after ${WAITED}s — check the bundle logs for [tenant-migration]"
done
echo "    schema ready"

note "registering the tenant's 'individual' idgen template"
TRESP=$(vm_curl "-X POST http://$BIP:8080/idgen/v3/template -H 'Content-Type: application/json' -H 'X-Tenant-ID: $CODE' -H 'X-User-ID: seed-script' -d '{\"templateCode\":\"individual\",\"config\":{\"template\":\"IND-{DATE:yyyy}-{SEQ}\",\"sequence\":{\"scope\":\"GLOBAL\",\"start\":1,\"padding\":{\"length\":6,\"char\":\"0\"}}}}'")
printf '%s' "$TRESP" | grep -q '"templateCode":"individual"' && echo "    template registered" || \
  { printf '%s' "$TRESP" | grep -qi "exists" && echo "    template already exists" || die "template create failed: $TRESP"; }

if ! $VERIFY; then
  note "done — tenant $CODE is ready"
  exit 0
fi

note "verify: creating a test individual with a mobile number"
MOBILE="9$(printf '%09d' $((RANDOM * RANDOM % 1000000000)))"
IRESP=$(vm_curl "-X POST http://$BIP:8080/individual/v3/individuals -H 'Content-Type: application/json' -H 'X-Tenant-ID: $CODE' -H 'X-User-ID: seed-script' -d '{\"givenName\":\"Seed\",\"familyName\":\"Verify\",\"mobileNumber\":\"$MOBILE\",\"gender\":\"OTHER\"}'")
IND_ID=$(printf '%s' "$IRESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('individualId',''))" 2>/dev/null || true)
[ -n "$IND_ID" ] || die "individual create failed: $IRESP"

P1=FAIL; printf '%s' "$IRESP" | grep -q "\"mobileNumber\":\"$MOBILE\"" && P1=PASS
ROW=$(psql_exec -d bundle_db -tAc "SELECT mobilenumber||'|'||hashedmobilenumber FROM \"$CODE\".individual_v3 WHERE individualid='$IND_ID'")
P2=FAIL; printf '%s' "$ROW" | grep -q "^vault:v1:" && ! printf '%s' "$ROW" | grep -q "$MOBILE" && P2=PASS
P3=FAIL; vault_exec 'vault list -format=json transit/keys' | grep -q "\"$CODE\"" && P3=PASS

echo
echo "  API returns plaintext mobile           : $P1  ($IND_ID)"
echo "  DB stores vault:v1 ciphertext + HMAC   : $P2"
echo "  per-tenant transit key exists in Vault : $P3"
[ "$P1$P2$P3" = "PASSPASSPASS" ] && note "verification PASSED" || die "verification FAILED — see the gotchas table in INSTALL.md"
