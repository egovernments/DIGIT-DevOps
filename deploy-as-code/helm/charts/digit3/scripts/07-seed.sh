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
#   custom grouping: ACCOUNT_SVC=<svc> [IDGEN_SVC=… INDIVIDUAL_SVC=… NOTIFICATION_SVC=… OTP_SVC=…] ./07-seed.sh …
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel
VERIFY=false
ARGS=()
for a in "$@"; do [ "$a" = "--verify" ] && VERIFY=true || ARGS+=("$a"); done
[ ${#ARGS[@]} -ge 2 ] || die "usage: $0 <tenant-name> <email> [phone-E164] [--verify]"
NAME="${ARGS[0]}" EMAIL="${ARGS[1]}" PHONE="${ARGS[2]:-+919999999999}"

svc_ip() { kubectl get svc "$1" -n egov -o jsonpath='{.spec.clusterIP}'; }
if [ -n "${ACCOUNT_SVC:-}" ]; then
  # Custom grouping (CUSTOM-BUNDLING.md §8): name the k8s Service that owns each seeded
  # endpoint and the shape file is not consulted. Unset ones default to ACCOUNT_SVC (one
  # bundle holding everything). Deployment names are the Service names for bundles.
  # Report the shape by its real name when 06-deploy.sh or CUSTOM-BUNDLING.md §6
  # recorded one; "custom" is only a fallback label for the log line.
  SHAPE=$(cat "$SCRIPT_DIR/.last-shape" 2>/dev/null || true); SHAPE=${SHAPE:-custom}
  IDGEN_SVC=${IDGEN_SVC:-$ACCOUNT_SVC}; INDIVIDUAL_SVC=${INDIVIDUAL_SVC:-$ACCOUNT_SVC}
  NOTIFICATION_SVC=${NOTIFICATION_SVC:-$ACCOUNT_SVC}; OTP_SVC=${OTP_SVC:-$ACCOUNT_SVC}
  ACCOUNT=$(svc_ip "$ACCOUNT_SVC"); IDGEN=$(svc_ip "$IDGEN_SVC"); INDIVIDUAL=$(svc_ip "$INDIVIDUAL_SVC")
  NOTIF=$(svc_ip "$NOTIFICATION_SVC"); OTP=$(svc_ip "$OTP_SVC")
  ACCOUNT_DEP=$ACCOUNT_SVC; IDGEN_DEP=$IDGEN_SVC; INDIVIDUAL_DEP=$INDIVIDUAL_SVC
else
  SHAPE=$(cat "$SCRIPT_DIR/.last-shape" 2>/dev/null || true)
  [ -n "$SHAPE" ] || die "scripts/.last-shape missing — run 06-deploy.sh first (or, for a custom grouping, set ACCOUNT_SVC and optionally IDGEN_SVC/INDIVIDUAL_SVC/NOTIFICATION_SVC/OTP_SVC to the owning Services)"
  case "$SHAPE" in dev-bundle) SHAPE=single-container ;; domain-split) SHAPE=domain-bundles ;; services) SHAPE=per-service ;; esac
  case "$SHAPE" in
    per-service)  ACCOUNT=$(svc_ip account); IDGEN=$(svc_ip idgen)
                  INDIVIDUAL=$(svc_ip individual); NOTIF=$(svc_ip notification); OTP=$(svc_ip otp)
                  ACCOUNT_DEP=account; IDGEN_DEP=idgen; INDIVIDUAL_DEP=individual ;;
    single-container) ACCOUNT=$(svc_ip dev-bundle); IDGEN=$ACCOUNT; INDIVIDUAL=$ACCOUNT; NOTIF=$ACCOUNT; OTP=$ACCOUNT
                  ACCOUNT_DEP=dev-bundle; IDGEN_DEP=dev-bundle; INDIVIDUAL_DEP=dev-bundle ;;
    domain-bundles) ACCOUNT=$(svc_ip identity-bundle); INDIVIDUAL=$ACCOUNT; OTP=$ACCOUNT
                  IDGEN=$(svc_ip admin-bundle); NOTIF=$(svc_ip notification-bundle)
                  ACCOUNT_DEP=identity-bundle; IDGEN_DEP=admin-bundle; INDIVIDUAL_DEP=identity-bundle ;;
    *) die "unknown shape in scripts/.last-shape: $SHAPE (custom grouping? set ACCOUNT_SVC …)" ;;
  esac
fi
[ -n "$ACCOUNT" ] || die "account-hosting service not found — is shape '$SHAPE' deployed?"
H_JSON="-H 'Content-Type: application/json'"

# Readiness pre-check: these calls run over ssh+curl, so an unready service
# surfaces as a bare curl failure — fail loudly and specifically instead.
check_ready() { # deploy-name
  local d="$1" ready
  ready=$(kubectl get deploy "$d" -n egov -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
  [ "${ready:-0}" -ge 1 ] 2>/dev/null || \
    die "service '$d' has no ready pod — check: kubectl get pods -n egov -l app=$d; a stale vault-approle secret is the classic cause (re-run ./04-vault.sh, then rollout restart)"
}
for d in $(printf '%s\n' "$ACCOUNT_DEP" "$IDGEN_DEP" "$INDIVIDUAL_DEP" | sort -u); do check_ready "$d"; done
# Keycloak is the slowest thing on a fresh VM (~100s to listen) and lives in
# its own namespace, so the egov readiness loop above misses it — tenant
# create calls its admin token endpoint and fails with a bare ConnectException
# if it races the boot. "Available" is only meaningful because the keycloak
# chart's readiness probe gates on /keycloak/realms/master answering; without
# that probe this wait returned the instant the container existed.
note "waiting for keycloak to be ready (admin API)"
kubectl wait --for=condition=Available deploy/keycloak -n keycloak --timeout=180s >/dev/null \
  || die "keycloak not Available after 180s — check: kubectl get pods -n keycloak; kubectl logs -n keycloak deploy/keycloak"
echo "    services ready"

print_credentials() {
  if [ -n "$ADMIN_PASS" ]; then
    echo
    echo "  tenant admin login (shown ONCE — store it now):"
    echo "    username: $EMAIL"
    echo "    password: $ADMIN_PASS"
  fi
}

note "creating tenant '$NAME' on shape '$SHAPE' (all calls run on the VM)"
# The tenant admin is created with this password — generated here and printed
# ONCE at the end. Without it the server generates one that is never delivered
# (SMTP is a placeholder in test environments).
ADMIN_PASS=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-16)
RESP=$(vm_curl "-X POST http://$ACCOUNT:8080/account/v3/tenants $H_JSON -H 'X-User-ID: seed-script' -d '{\"name\":\"$NAME\",\"email\":\"$EMAIL\",\"phone\":\"$PHONE\",\"password\":\"$ADMIN_PASS\"}'")
CODE=$(printf '%s' "$RESP" | python3 -c "import sys,json;print(json.load(sys.stdin).get('code',''))" 2>/dev/null || true)
if [ -z "$CODE" ]; then
  CODE=$(vm_curl "'http://$ACCOUNT:8080/account/v3/tenants?email=$EMAIL'" | \
    python3 -c "import sys,json;ts=json.load(sys.stdin).get('tenants') or [];print(ts[0]['code'] if ts else '')" 2>/dev/null || true)
  [ -n "$CODE" ] && { echo "    tenant already exists (admin password unchanged)"; ADMIN_PASS=""; } || die "tenant create failed: $RESP"
fi
echo "    tenant code: $CODE"
# Printed IMMEDIATELY, not at the end: a failure in any later step would
# otherwise lose a password that was already written into Keycloak.
print_credentials

note "waiting for the tenant-migration fan-out to COMPLETE for '$CODE'"
# Schema existence is NOT completion: the first consumer creates the schema
# within a second, while the other 14 are still migrating — seeding a service
# whose tables don't exist yet fails with an opaque 500 (proven live: otp's
# event arrived 1.3s AFTER the schema already existed). All 15 tenant-migrating
# services leave a <svc>_schema Flyway history table; wait for every one.
WAITED=0
until [ "$(psql_exec -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='$CODE' AND tablename LIKE '%_schema'")" = "15" ]; do
  sleep 3; WAITED=$((WAITED + 3))
  [ "$WAITED" -ge 300 ] && die "tenant fan-out incomplete after ${WAITED}s ($(psql_exec -tAc "SELECT count(*) FROM pg_tables WHERE schemaname='$CODE' AND tablename LIKE '%_schema'")/15 histories) — check [tenant-migration] in the consumer logs"
done
echo "    fan-out complete (15/15 service migrations)"

hdr() { echo "-H 'X-Tenant-ID: $CODE' -H 'X-User-ID: seed-script'"; }
seed() { # label url json ok-marker — one retry: a service's very first request
  # after rollout can 500 while pools/clients warm up (readiness can't see it)
  local out attempt
  for attempt in 1 2; do
    out=$(vm_curl "-X POST $2 $H_JSON $(hdr) -d '$3'")
    if printf '%s' "$out" | grep -q "$4"; then echo "    $1: created"; return 0
    elif printf '%s' "$out" | grep -qiE "exists|conflict|409"; then echo "    $1: already present"; return 0
    fi
    [ "$attempt" = 1 ] && { echo "    $1: transient ($(printf '%s' "$out" | head -c 60)…) — retrying"; sleep 5; }
  done
  die "$1 failed: $out"
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
