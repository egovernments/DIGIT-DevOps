#!/usr/bin/env bash
# 09 — the License & Permits (LnP) overlay on top of whichever shape 06-deploy.sh installed.
# Additive and idempotent: it never touches the shape's own releases. See ../LNP.md.
#
#   ./09-lnp.sh <path-to-digit3-repo> <master-tenant-admin-email>
#
# What it does, in order:
#   1. secrets  — `license-certificate` entry in this environment's sops file (older files lack it),
#                 then cluster-configs re-sync so the Secret exists
#   2. tenant   — "Base Tenant" → code BASETENANT (LnP's master-tenant schema) via 07-seed.sh;
#                 its auth-server client secret → sops → cluster-configs
#   3. overlay  — DOMAIN/DIGIT_SHAPE ./deploy.sh -f lnp-helmfile.yaml sync, rollouts
#   4. kong     — setup.py with KONG_EXTRA_ROUTES=lnp/kong-routes.json (catalogue routes re-applied, no-op)
#   5. onboard  — POST /license/onboarding/_onboard-tenant; 5b. lnp/seed-master-data.sh: certificate types,
#                 workflows, billing/tax heads, idgen + OTP templates, document categories (lnp/exports);
#                 5c. /license/access-control/_provision-* (Keycloak authz objects + MDMS UI actions)
#                 workflows, billing/tax heads, idgen + OTP templates, document categories (lnp/exports) as the BASETENANT admin: LnP provisions its
#                 own master data (certificate types, calculator rules, schemas, pdf templates, MDMS,
#                 localisation, VC tenant) — the services' own seeding path, not SQL
#   6. smoke    — certificate types through Kong, the four UIs through the ingress
# The BASETENANT admin password is printed ONCE by 07-seed.sh (same handling as any tenant — see
# INSTALL.md / the install-digit skill §3); this script reads it from its own capture only to mint
# the onboarding token and never prints it.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel
[ $# -ge 2 ] || die "usage: $0 <path-to-digit3-repo> <master-tenant-admin-email>"
DIGIT3="$(cd "$1" && pwd)"; EMAIL="$2"
TENANT_NAME="BASETENANT"; TENANT="BASETENANT"   # name == code: the LnP UIs resolve the tenant with GET /accounts/v3/tenants?name=<code>
SHAPE=$(cat "$SCRIPT_DIR/.last-shape" 2>/dev/null || true)
[ -n "$SHAPE" ] || die "scripts/.last-shape missing — run 06-deploy.sh first (the overlay follows the deployed shape)"
[ -f "$CHART_DIR/$SHAPE-helmfile.yaml" ] || die "no $SHAPE-helmfile.yaml — custom groupings: deploy the overlay by hand (LNP.md §custom)"
export DOMAIN DIGIT_SHAPE="$SHAPE"
LNP_DIR="$CHART_DIR/lnp"

# ---- 1. secrets ---------------------------------------------------------------------------------
note "1/6 secrets: license-certificate entry in $(basename "$SECRETS_FILE")"
if [ -z "$(sops_get 'cluster-configs.secrets.license-certificate.certificate-otp-bypass-code' 2>/dev/null)" ]; then
  # <= 20 chars: license-certificate validates otp.code with @Size(max = 20), a longer bypass code can never be entered
  sops_set 'cluster-configs.secrets.license-certificate.certificate-otp-bypass-code' "$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-16)"
  sops_set 'cluster-configs.secrets.license-certificate.egov-keycloak-client-secret' ""
  echo "    added (otp bypass code generated; client secret filled in step 2)"
else
  echo "    present"
fi

# ---- 2. master tenant + its auth-server client secret -------------------------------------------
note "2/6 tenant $TENANT (\"$TENANT_NAME\", $EMAIL) via 07-seed.sh"
SEED_CAP="$HOME/lnp-seed-$DOMAIN.log"
# 07 prints the password only on the run that creates the tenant; a re-run says "tenant already
# exists". Capture to a scratch file and promote it only when it holds a fresh password, so an
# earlier capture (the only copy) is never overwritten by a re-run.
NEW_CAP=$(umask 077; mktemp "$HOME/.lnp-seed.XXXXXX")
( "$SCRIPT_DIR/07-seed.sh" "$TENANT_NAME" "$EMAIL" > "$NEW_CAP" 2>&1 ) || { cat "$NEW_CAP"; rm -f "$NEW_CAP"; die "07-seed.sh failed"; }
grep -vE "^\s+password: " "$NEW_CAP"            # everything 07 said, minus the one-time value
grep -q "tenant code: $TENANT" "$NEW_CAP" || { rm -f "$NEW_CAP"; die "07-seed.sh did not report tenant code $TENANT"; }
if grep -q "shown ONCE" "$NEW_CAP"; then
  mv "$NEW_CAP" "$SEED_CAP"
  echo "    the one-time admin password is in $SEED_CAP (label: 'tenant admin login') — store it, then: shred -u $SEED_CAP"
else
  rm -f "$NEW_CAP"
fi

note "    auth-server client secret of realm $TENANT -> sops -> cluster-configs"
KCIP=$(kubectl get svc keycloak -n keycloak -o jsonpath='{.spec.clusterIP}')
KCUSER=$(sops_get 'cluster-configs.secrets.kc-admin.username')
CSEC=$( printf '%s\n%s\n' "$KCUSER" "$(sops_get 'cluster-configs.secrets.kc-admin.password')" | \
  vm_ssh "read -r KCUSER; read -r KCPW
KC='http://keycloak.keycloak.svc.cluster.local:8080/keycloak'
RES='--resolve keycloak.keycloak.svc.cluster.local:8080:$KCIP'
ADM=\$(curl -s \$RES -X POST \$KC/realms/master/protocol/openid-connect/token \
  --data-urlencode grant_type=password --data-urlencode client_id=admin-cli \
  --data-urlencode \"username=\$KCUSER\" --data-urlencode \"password=\$KCPW\" | \
  python3 -c 'import sys,json;print(json.load(sys.stdin).get(\"access_token\",\"\"))')
[ -n \"\$ADM\" ] || { echo NOADMIN; exit 0; }
CID=\$(curl -s \$RES -H \"Authorization: Bearer \$ADM\" \"\$KC/admin/realms/$TENANT/clients?clientId=auth-server\" | \
  python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0][\"id\"] if d else \"\")')
[ -n \"\$CID\" ] || { echo NOCLIENT; exit 0; }
curl -s \$RES -H \"Authorization: Bearer \$ADM\" \$KC/admin/realms/$TENANT/clients/\$CID/client-secret | \
  python3 -c 'import sys,json;print(json.load(sys.stdin).get(\"value\",\"\"))'" )
case "$CSEC" in
  NOADMIN)  die "keycloak admin login failed (kc-admin secret vs cluster mismatch?)" ;;
  NOCLIENT) die "realm $TENANT has no auth-server client — did the tenant create succeed?" ;;
  "")       die "empty client secret returned" ;;
esac
sops_set 'cluster-configs.secrets.license-certificate.egov-keycloak-client-secret' "$CSEC"; unset CSEC
echo "    re-syncing cluster-configs via $SHAPE-helmfile.yaml (keeps the shape's service-host map)"
"$DEPLOY" -f "$SHAPE-helmfile.yaml" -l name=cluster-configs sync >/dev/null
kubectl get secret license-certificate -n egov >/dev/null || die "Secret license-certificate not created by cluster-configs"

# ---- 3. overlay ---------------------------------------------------------------------------------
note "3/6 overlay: deploy.sh -f lnp-helmfile.yaml sync  (DOMAIN=$DOMAIN DIGIT_SHAPE=$SHAPE)"
"$DEPLOY" -f lnp-helmfile.yaml sync
for d in mdms-v2 walt calculator schema-registry pdf-v3 vc license-certificate license-admin license-citizen license-employee license-validator; do
  kubectl rollout status "deploy/$d" -n egov --timeout=600s
done

# ---- 4. kong ------------------------------------------------------------------------------------
note "4/6 kong: catalogue routes (+ in-cluster proxy hostnames) + lnp/kong-routes.json"
kubectl port-forward -n egov svc/kong-kong-admin 18001:8001 >/dev/null 2>&1 &
PF_PID=$!; trap 'kill $PF_PID 2>/dev/null || true' EXIT
for _ in $(seq 1 30); do curl -sfm 2 -o /dev/null http://localhost:18001/status && break; sleep 2; done
case "$SHAPE" in
  per-service)      KONG_BUNDLES="none" ;;
  single-container) KONG_BUNDLES="" ;;
  domain-bundles)   KONG_BUNDLES="$DIGIT3/src/bundles/domain-split.package.yaml" ;;
esac
(cd "$DIGIT3/src/services/kong" && \
  env KONG_ADMIN_URL=http://localhost:18001 KONG_ROUTE_HOSTS="$DOMAIN,kong-kong-proxy.egov.svc.cluster.local,kong-kong-proxy.egov" KONG_EXTRA_ROUTES="$LNP_DIR/kong-routes.json" \
      ${KONG_BUNDLES:+KONG_BUNDLE_MANIFESTS="$KONG_BUNDLES"} python3 setup.py | grep -E "^Extra routes|✓ route .*(license|calculator|pdf|schema|credential|mdms)|Done")

# ---- 5. onboard ---------------------------------------------------------------------------------
note "5/6 onboarding $TENANT through license-certificate (its own provisioning path)"
KGIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
# The admin password lives only in the 07 capture (or, on a re-run, in the caller's hands): read it in
# the same command that uses it, never echo it. Re-runs with the tenant already seeded need LNP_ADMIN_PASSWORD.
PW=$( [ -f "$SEED_CAP" ] && sed -n 's/^\s*password: //p' "$SEED_CAP" | head -1 ); PW=${PW:-${LNP_ADMIN_PASSWORD:-}}
[ -n "$PW" ] || die "no admin password available — re-run with LNP_ADMIN_PASSWORD=<the one 07-seed printed> in the environment"
TOKEN=$("$SCRIPT_DIR/08-token.sh" "$TENANT" "$EMAIL" "$PW" 2>/dev/null | grep -E '^ey[A-Za-z0-9_-]+\.' | head -1); unset PW
[ -n "$TOKEN" ] || die "08-token.sh returned no token for $EMAIL in $TENANT"
RESP=$(printf '%s\n' "$TOKEN" | vm_ssh "read -r T; curl -s -m 600 -X POST http://$KGIP:8000/license/onboarding/_onboard-tenant \
  -H 'Host: $DOMAIN' -H 'X-Tenant-ID: $TENANT' -H 'X-User-Id: 09-lnp' -H 'Content-Type: application/json' -H \"Authorization: Bearer \$T\" -d '{}'")
printf '%s' "$RESP" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: print("    non-JSON reply:", sys.stdin.read()[:300] if False else "see above"); raise SystemExit(1)
steps=d.get("steps") or {}
val=lambda v: str(v.get("status",v)) if isinstance(v,dict) else str(v)
bad=[k for k,v in steps.items() if any(w in val(v).upper() for w in ("FAIL","ERROR","ABORT","EXCEPTION"))]
for k,v in steps.items(): print("    %-28s %s" % (k, val(v)[:150]))
print("    steps with problems:", bad or "none")' || { printf "%s" "$RESP" > "$HOME/lnp-onboard-$DOMAIN.json"; die "onboarding call failed — full reply in $HOME/lnp-onboard-$DOMAIN.json: ${RESP:0:300}"; }

# ---- 5b. master data ---------------------------------------------------------------------------
note "5b/6 master data (certificate types, workflows, fee config, templates) from lnp/exports"
PWF=$(umask 077; mktemp "$HOME/.lnp-pw.XXXXXX"); { [ -f "$SEED_CAP" ] && sed -n 's/^\s*password: //p' "$SEED_CAP" | head -1 || printf '%s' "${LNP_ADMIN_PASSWORD:-}"; } > "$PWF"
"$LNP_DIR/seed-master-data.sh" "$TENANT" "$EMAIL" "$PWF" || die "master data seeding failed"; rm -f "$PWF"

# ---- 5c. access control ------------------------------------------------------------------------
# LnP's Keycloak authorization objects (scopes, resources, roles, policies, permissions on the shared
# auth-server client) and the MDMS UI-action mapping — the second provisioning block _onboard-tenant
# leaves out. The three Keycloak calls take the tenant super-user's email+password in the body (the
# service's own contract); the value is read from the capture in the same command, never printed.
note "5c/6 access control: Keycloak authz objects + MDMS UI actions for $TENANT"
ACPW=$( [ -f "$SEED_CAP" ] && sed -n 's/^\s*password: //p' "$SEED_CAP" | head -1 ); ACPW=${ACPW:-${LNP_ADMIN_PASSWORD:-}}
CRED=$(python3 -c 'import json,sys; print(json.dumps({"email": sys.argv[1], "password": sys.argv[2]}))' "$EMAIL" "$ACPW"); unset ACPW
for ep in _provision-scopes-and-resources _provision-roles-and-policies _provision-permissions _provision-ui-actions; do
  body="$CRED"; [ "$ep" = _provision-ui-actions ] && body='{}'
  RESP=$(printf '%s\n%s' "$TOKEN" "$body" | vm_ssh "read -r T; curl -s -m 300 -X POST http://$KGIP:8000/license/access-control/$ep \
    -H 'Host: $DOMAIN' -H 'X-Tenant-ID: $TENANT' -H 'X-User-Id: 09-lnp' -H 'Content-Type: application/json' -H \"Authorization: Bearer \$T\" -d @-")
  printf '%s' "$RESP" | python3 -c '
import sys,json,collections
ep=sys.argv[1]
try: d=json.load(sys.stdin)
except Exception: print("    %-34s non-JSON reply" % ep); raise SystemExit(1)
st=d.get("steps") or {}; c=collections.Counter(str(v).split(":")[0].split(" ")[0] for v in st.values())
bad=[k for k,v in st.items() if str(v).upper().startswith("FAILED")]
print("    %-34s %s%s" % (ep, dict(c), ("  FAILED: "+", ".join(bad[:5])) if bad else ""))' "$ep" || die "access-control $ep failed: ${RESP:0:200}"
done; unset CRED

# ---- 6. smoke -----------------------------------------------------------------------------------
note "6/6 smoke"
CT=$(printf '%s\n' "$TOKEN" | vm_ssh "read -r T; curl -s -o /dev/null -w '%{http_code}' -H 'Host: $DOMAIN' -H 'X-Tenant-ID: $TENANT' -H 'X-User-Id: 09-lnp' -H \"Authorization: Bearer \$T\" http://$KGIP:8000/license/certificate-types"); unset TOKEN
echo "    GET /license/certificate-types via kong -> HTTP $CT"
for u in license/admin license/citizen license/employee license/validator; do
  printf '    https://%s/%s -> HTTP %s\n' "$DOMAIN" "$u" "$(curl -sk -o /dev/null -m 15 -w '%{http_code}' "https://$DOMAIN/$u/")"
done
echo
echo "LnP overlay deployed on shape '$SHAPE' at https://$DOMAIN/license/{admin,citizen,employee,validator}"
next "log in to https://$DOMAIN/license/admin as $EMAIL (password from $SEED_CAP, then shred it)"
