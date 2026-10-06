#!/usr/bin/env bash
# LnP master data for the BASETENANT tenant — everything `_onboard-tenant` does NOT provision on a
# fresh platform (it inflates schemas and copies theme/localisation, but the certificate types,
# their workflows, fee rules' tax heads, idgen templates and OTP templates come from the LnP team's
# environment). Sources: lnp/exports/* captured read-only from test-lts. Idempotent: every call is a
# create-if-absent or a no-op on conflict. Called by 09-lnp.sh after onboarding; safe to re-run alone:
#   lnp/seed-master-data.sh <tenant> <admin-email> <admin-password-file> [all|data|menus]
# `menus` needs the mdms access.* schemas, which /license/access-control/_provision-ui-actions creates;
# 09-lnp.sh therefore runs `data` before access control and `menus` after it.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); SCRIPTS="$HERE/../scripts"; EXPORTS="$HERE/exports"
source "$SCRIPTS/lib.sh"; load_env; set +e; trap - ERR
TENANT=$1; EMAIL=$2; PWFILE=$3; ONLY=${4:-all}
case "$ONLY" in all|data|menus) ;; *) die "mode must be all, data or menus (got $ONLY)";; esac
KGIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
TOK=$(umask 077; mktemp "$HOME/.lnp-tok.XXXXXX"); trap 'rm -f "$TOK"' EXIT
pw=$(sed -n 's/^\s*password: //p' "$PWFILE" | head -1); [ -n "$pw" ] || pw=$(cat "$PWFILE")
"$SCRIPTS/08-token.sh" "$TENANT" "$EMAIL" "$pw" 2>/dev/null | grep -E '^ey[A-Za-z0-9_-]+\.' | head -1 > "$TOK"; unset pw
[ -s "$TOK" ] || die "could not mint a token for $EMAIL in $TENANT"
api() { # api METHOD path [body] -> CODE BODY (token + body over the ssh stdin)
  local out; out=$( { cat "$TOK"; printf '%s' "${3:-}"; } | vm_ssh "read -r T; curl -s -m 90 -w '\n%{http_code}' -X $1 'http://$KGIP:8000$2' -H 'Host: $DOMAIN' -H 'X-Tenant-ID: $TENANT' -H 'X-User-Id: 09-lnp' -H 'X-Client-ID: 09-lnp' -H 'Content-Type: application/json' -H \"Authorization: Bearer \$T\" ${3:+-d @-}")
  CODE=${out##*$'\n'}; BODY=${out%$'\n'*}
}
j() { printf '%s' "$BODY" | python3 -c "import sys,json; d=json.load(sys.stdin); print($1)" 2>/dev/null || true; }
tally() { case "$CODE" in 200|201) echo "created";; 409) echo "exists";; 400) case "$BODY" in *CONFLICT*|*"already exists"*) echo "exists";; *) echo "HTTP $CODE ${BODY:0:100}";; esac;; *) echo "HTTP $CODE ${BODY:0:100}";; esac; }

if [ "$ONLY" != menus ]; then
note "master data: certificate types, categories, rules, schemas, templates (SQL from lnp/exports/db)"
for f in basetenant-lnp-config.sql basetenant-required-document.sql public-lnp-config.sql; do
  errs=$(psql_exec -v ON_ERROR_STOP=0 -q < "$EXPORTS/db/$f" 2>&1 | grep -c "ERROR" || true)
  echo "    $f: applied ($errs duplicate-key/no-op errors)"
done
# the SQL carries BASETENANT's schema name literally; a different master tenant needs the dump re-pointed
[ "$TENANT" = "BASETENANT" ] || echo "    WARNING: exports target schema BASETENANT, tenant is $TENANT — review lnp/exports/db"

note "master data: workflow process definitions"
for f in "$EXPORTS"/workflow/*.json; do c=$(basename "$f" .json)
  api GET "/workflow/v3/process/definition?processCode=$c"; if [ "$(j 'd.get("totalCount",0)')" != "0" ]; then echo "    $c: exists"; continue; fi
  api POST /workflow/v3/process/definition "$(python3 "$HERE/wf-transform.py" "$f")"; echo "    $c: $(tally)"; done

note "master data: billing business services + tax heads (export, then whatever the calculator rules reference)"
api GET /billing/v3/business-services; HAVE_BS=$(j '",".join(b["code"] for b in (d if isinstance(d,list) else d.get("businessServices",d.get("data",[]))))')
BS=$(python3 -c '
import json,sys; have=set(sys.argv[2].split(",")); out=[]
for b in json.load(open(sys.argv[1])):
    if b["code"] in have: continue
    e={k:v for k,v in b.items() if k in ("code","name","collectionMode","allowedPaymentModes","billExpiryDays","partialPaymentAllowed","minPayableAmount","currency","roundingRuleCode","effectiveFrom","effectiveTo","isActive")}
    if e.get("collectionMode") not in ("ONLINE","OFFLINE","COUNTER","FIELD"): e["collectionMode"]="ONLINE"
    e.setdefault("currency","INR"); e.setdefault("isActive",True); e.setdefault("billExpiryDays",15); out.append(e)
print(json.dumps(out))' "$EXPORTS/testlts-billing-business-services.BASETENANT.json" "$HAVE_BS")
[ "$BS" = "[]" ] && echo "    business services: all present" || { api POST /billing/v3/business-services "$BS"; echo "    business services: $(j 'len(d)') $(tally)"; }
api GET /billing/v3/tax-heads; HAVE_TH=$(j '",".join(t["code"] for t in (d if isinstance(d,list) else d.get("taxHeads",d.get("data",[]))))')
TH=$(python3 -c '
import json,sys; have=set(sys.argv[2].split(",")); out=[]
for t in json.load(open(sys.argv[1])):
    if t["code"] in have: continue
    e={k:v for k,v in t.items() if k in ("code","name","businessServiceCode","category","order","effectiveFrom","effectiveTo","isActive")}
    if e.get("category") not in ("TAX","CESS","PENALTY","INTEREST","REBATE","ROUNDING","ARREAR"): e["category"]="TAX"
    out.append(e)
print(json.dumps(out))' "$EXPORTS/testlts-billing-tax-heads.BASETENANT.json" "$HAVE_TH")
[ "$TH" = "[]" ] && echo "    tax heads (export): all present" || { api POST /billing/v3/tax-heads "$TH"; echo "    tax heads (export): $(j 'len(d)') $(tally)"; }
api GET /billing/v3/tax-heads; HAVE_TH=$(j '",".join(t["code"] for t in (d if isinstance(d,list) else d.get("taxHeads",d.get("data",[]))))')
api GET /license/certificate-types; TYPES=$(j '" ".join(t["code"] for t in d.get("certificateTypes",[]))')
NOW=$(date +%s000); EXTRA="["; SEP=""
for ct in $TYPES; do
  api GET "/calculator/calculation/v3/$ct/rules"; n=10
  for c in $(j '" ".join(sorted({r["component"] for r in (d if isinstance(d,list) else d.get("rules",d.get("data",[]))) if r.get("component")}))'); do
    echo ",$HAVE_TH," | grep -q ",$c," && continue
    case $c in *_REBATE*) cat=REBATE;; *_PENALTY*) cat=PENALTY;; *_INTEREST*) cat=INTEREST;; *_ARREAR*) cat=ARREAR;; *) cat=TAX;; esac
    name=$(echo "${c#${ct}_}" | tr '_' ' ')
    EXTRA="$EXTRA$SEP{\"code\":\"$c\",\"name\":\"$name\",\"businessServiceCode\":\"$ct\",\"category\":\"$cat\",\"order\":$n,\"effectiveFrom\":$NOW,\"isActive\":true}"; SEP=","; n=$((n+10)); done
done; EXTRA="$EXTRA]"
[ "$EXTRA" = "[]" ] && echo "    tax heads (from rules): all present" || { api POST /billing/v3/tax-heads "$EXTRA"; echo "    tax heads (from rules): $(j 'len(d)') $(tally)"; }

note "master data: Business License files without a category (its form has no category control; the type's taxonomy would make every citizen submission fail with 'category is required')"
api GET /license/certificate-types/BUSINESS_LICENSE
if [ "$(j 'str((d.get("categoryConfig") or {}).get("enabled"))')" = "True" ]; then
  api PUT /license/certificate-types/BUSINESS_LICENSE "$(j 'json.dumps({**{k:v for k,v in d.items() if k not in ("auditDetail","dashboards","id","tenantId","configVersion","version")}, "categoryConfig": {"enabled": False}})')"
  echo "    BUSINESS_LICENSE categoryConfig.enabled=false: $(tally)"
else echo "    BUSINESS_LICENSE: no category taxonomy (ok)"; fi

note "master data: idgen templates per certificate type"
for ct in $TYPES; do
  api GET "/license/certificate-types/$ct"; P=$(echo "$ct" | cut -c1-2)
  for pair in "$(j 'd["idFormatConfig"]["applicationIdTemplateCode"]'):${P}A" "$(j 'd["idFormatConfig"]["certificateIdTemplateCode"]'):${P}C"; do code=${pair%%:*}; [ -n "$code" ] && [ "$code" != "None" ] || continue
    api POST /idgen/v3/template "{\"templateCode\":\"$code\",\"config\":{\"template\":\"${pair##*:}-{DATE:yyyy}-{SEQ}\",\"sequence\":{\"scope\":\"GLOBAL\",\"start\":1,\"padding\":{\"length\":6,\"char\":\"0\"}}}}"; echo "    $code: $(tally)"; done
done

note "master data: OTP notification templates (otp maps non-login purposes to *-otp-generic; the Keycloak e-mail OTP login flow LnP installs uses email-otp-login). SMS text is the DLT-approved template — operators drop any other wording"
api POST /notification/v3/template '{"templateId":"sms-otp-generic","type":"SMS","content":"Dear Citizen, Your Login OTP is {{.otp}}\n\nEGOVS"}'; echo "    sms-otp-generic: $(tally)"
api POST /notification/v3/template '{"templateId":"email-otp-login","type":"EMAIL","subject":"Your login code","content":"Your login code is {{ .otp }}. Valid 5 minutes."}'; echo "    email-otp-login: $(tally)"
api POST /notification/v3/template '{"templateId":"email-otp-generic","type":"EMAIL","subject":"Your verification code","content":"Your verification code is {{ .otp }}. Valid 5 minutes."}'; echo "    email-otp-generic: $(tally)"

note "master data: filestore document categories every certificate type requires"
api GET /filestore/v3/document-categories; HAVE_DC=$(j '",".join(x["code"] for x in d)')
for c in $(psql_exec -tAc "SELECT DISTINCT document_type FROM \"$TENANT\".required_document" 2>/dev/null); do
  echo ",$HAVE_DC," | grep -q ",$c," && continue
  api POST /filestore/v3/document-categories "{\"code\":\"$c\",\"type\":\"certificate\",\"allowedFormats\":[\"pdf\",\"jpg\",\"png\"],\"maxSize\":\"10MB\",\"isSensitive\":false,\"description\":\"$c\"}"; echo "    $c: $(tally)"; done
fi

[ "$ONLY" = data ] && { echo "    done"; exit 0; }
[ "$ONLY" = menus ] && { api GET /license/certificate-types; TYPES=$(j '" ".join(t["code"] for t in d.get("certificateTypes",[]))'); }
note "master data: employee-portal menus (mdms access.UIActions + PermissionActions) per certificate type"
# license-certificate derives LC_<CODE>_{MODULE,REPORTS,INBOX,SEARCH,APPLY} only when a type is created through its API;
# _provision-ui-actions ships a static manifest (TRADE_LICENSE, FIRE_NOC, ...), so SQL-imported types such as
# BUSINESS_LICENSE have no menu and the employee portal hides them. Same derivation as CertificateTypeMenuProvisioningService.
for ct in $TYPES; do
  api GET "/mdms-v2/v2?schemaCode=access.UIActions&uniqueIdentifiers=LC_$(echo "$ct" | sed 's/[^A-Za-z0-9]\+/_/g; s/^_//; s/_$//' | tr a-z A-Z)_MODULE"
  [ "$(j 'len(d.get("mdms",[]))')" = "0" ] || { echo "    $ct: exists"; continue; }
  for kind in ui perm; do api POST /mdms-v2/v2 "$(python3 - "$TENANT" "$ct" "$kind" <<'PY'
import json,re,sys
t,ct,kind=sys.argv[1:4]; u=re.sub(r'[^A-Za-z0-9]+','_',ct).strip('_').upper(); sid=u.lower(); P=f"LC_{u}"
meta={"certificateTypeCode":sid.replace('_','-'),"uiServiceId":sid}; name=" ".join(w.capitalize() for w in sid.split('_'))
ui=[("MODULE",name,"MODULE","","Business","LC_ROOT_MODULE",10),("REPORTS","Dashboard","LINK","/reports","Dashboard",f"{P}_MODULE",1),
    ("INBOX","Review Applications","LINK",f"/inbox?serviceId={sid}","AllInbox",f"{P}_MODULE",2),("SEARCH","Search","LINK",f"/search?serviceId={sid}","Search",f"{P}_MODULE",3),
    ("APPLY","Apply on behalf of citizen","ACTION",f"/apply/{sid}","ManageUsers",f"{P}_MODULE",4)]
perm={"MODULE":"certificates-by-type#get","REPORTS":"certificate-types#dashboard-view","INBOX":"certificates-by-type#get","SEARCH":"certificates-by-type#get","APPLY":"certificates-by-type#post"}
if kind=="ui": recs=[{"schemaCode":"access.UIActions","tenantId":t,"uniqueIdentifier":f"{P}_{s}","data":{"code":f"{P}_{s}","displayName":d,"type":ty,"navigationURL":url,"leftIcon":ic,"serviceCode":"LICENSE_CERTIFICATE","parentModule":pm,"orderNumber":o,"metadata":meta}} for s,d,ty,url,ic,pm,o in ui]
else: recs=[{"schemaCode":"access.PermissionActions","tenantId":t,"uniqueIdentifier":f"{pc}::{P}_{s}","data":{"actionCode":f"{P}_{s}","mappingKey":f"{pc}::{P}_{s}","permissionCode":pc}} for s,pc in perm.items()]
print(json.dumps({"Mdms":recs}))
PY
)"; echo "    $ct $kind: $(tally)"; done
done
echo "    done"
