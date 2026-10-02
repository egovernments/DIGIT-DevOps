#!/bin/bash
# LnP end-to-end API scenario on one VM (BUSINESS_LICENSE): admin config surface, citizen apply + OTP bypass,
# employee transitions by role, counter payment, issuance (VC + PDF), lifecycle, realm-policy proof.
# Usage: scenario.sh <scripts-dir> <admin-email> <admin-capture-file> <test-users-env>
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); source "$HERE/lib-api.sh" "$1" BASETENANT "$2" "$3"; USERS=$4; source "$USERS"
: > "$REPORT"; STAMP=$(date +%H%M%S); CT=BUSINESS_LICENSE; USERDOM=${USERDOM:-$DOMAIN}
as() { local pw="PW_$1"; printf '%s\n' "${!pw}" > /tmp/.pw.$$; chmod 600 /tmp/.pw.$$; mint BASETENANT "lnp-$1@$USERDOM" /tmp/.pw.$$ >/dev/null; rm -f /tmp/.pw.$$; }
as_admin() { mint BASETENANT "$2" "$3" >/dev/null; }
upload() { # upload <docType> <module> -> FSID (a tiny PDF made on the VM, multipart to filestore via kong)
  local out; out=$(cat "$TOKFILE" | vm_ssh "read -r T; printf '%%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%%%EOF\n' > /tmp/lnp-doc.pdf; curl -s -m 60 -w '\n%{http_code}' -X POST 'http://$KGIP:8000/filestore/v3/files/upload?module=$2&tag=$1' -H 'Host: $DOMAIN' -H 'X-Tenant-ID: $TENANT' -H 'X-User-Id: lnp-test' -H \"Authorization: Bearer \$T\" -F 'file=@/tmp/lnp-doc.pdf;type=application/pdf'")
  CODE=${out##*$'\n'}; BODY=${out%$'\n'*}; FSID=$(jq_ '(d if isinstance(d,list) else d.get("files") or d.get("data") or [d])[0].get("fileStoreId") or (d if isinstance(d,list) else [d])[0].get("id")')
}
tr_() { api POST "/license/certificate-types/$CT/certificates/$APP" "$1"; }
st_() { jq_ 'd.get("status")'; }; wf_() { jq_ '(d.get("workflow") or {}).get("currentState") or d.get("currentState")'; }
echo "scenario stamp $STAMP" >> "$REPORT"

echo "## A. admin — configuration surface"; as_admin x "$2" "$3"
api GET "/license/certificate-types?isActive=true";            check "A1 list live types (admin)" 200; echo "     $(jq_ '[t["code"] for t in d["certificateTypes"]]')"
api GET "/license/certificate-types/$CT";                       check "A2 GET type $CT" 200
api GET "/license/certificate-types/$CT/categories";            check "A3 categories" 200
api GET "/license/certificate-types/$CT/categories/food.restaurant.dinein"; check "A4 GET one category by path" 200
api GET "/license/certificate-types/$CT/deployment-history";    check "A5 deployment history" 200
api GET "/schema/certificate/$CT.form/schema";                  check "A6 schema-registry form schema" 200
api GET "/schema/certificate/$CT.checklist/schema";             check "A7 schema-registry checklist schema" 200
api GET "/workflow/v3/process/definition?processCode=$CT";      check "A8 workflow definition" 200
api GET "/calculator/calculation/v3/$CT/rules";                 check "A9 calculator rules" 200
api GET "/billing/v3/business-services/$CT";                    check "A10 billing business service" 200
api GET "/billing/v3/tax-heads?businessServiceCode=$CT";        check "A11 billing tax heads" 200
api GET "/credential/$CT";                                      check "A12 vc credential type" 200
api GET "/pdf-v3/$CT/template";                                 check "A13 pdf-v3 templates for type" "200|404"
NEW="TESTTYPE$STAMP"
api POST /license/certificate-types "{\"code\":\"$NEW\",\"name\":\"Test Type $STAMP\",\"description\":\"scenario\",\"sector\":\"TRADE\",\"instrumentType\":\"PERMIT\",\"allowedIssueType\":\"INDIVIDUAL\",\"validityMode\":\"FIXED\",\"validityPeriodDays\":365,\"gracePeriodDays\":30,\"isRenewable\":true,\"autoApprove\":false,\"isActive\":false,\"templateCode\":\"$CT\",\"requiredDocuments\":[{\"documentType\":\"ID_CARD_OR_PASSPORT\",\"mandatory\":true}],\"categoryConfig\":{\"enabled\":true,\"noOfLevels\":1,\"levelNames\":[\"Kind\"],\"mandatoryUpToLevel\":1},\"boundaryConfig\":{\"enabled\":false}}"; check "A14 create draft type (from template $CT)" "200|201"
api GET "/license/certificate-types/$NEW";                      check "A15 GET draft type" 200; FULL=$BODY
strip() { printf '%s' "$FULL" | python3 -c 'import sys,json; d=json.load(sys.stdin); exec(sys.argv[1]); [d.pop(k,None) for k in ("auditDetail","dashboards","id","tenantId","configVersion","version")]; print(json.dumps(d))' "$1"; }
api PUT "/license/certificate-types/$NEW" "$(strip 'd["description"]="scenario - minor edit"')"; check "A16 PUT minor edit (draft)" 200
api PUT "/license/certificate-types/$NEW" "$(strip 'd["isActive"]=True')"; check "A17 Go Live (PUT isActive=true)" 200
api GET "/license/certificate-types/$NEW/deployment-history";   check "A18 deployment history has the go-live" 200; echo "     entries: $(jq_ 'len(d if isinstance(d,list) else d.get("history",d.get("data",[])))')"
api POST "/license/certificate-types/$NEW/categories" "{\"path\":\"test\",\"isActive\":true}"; check "A19 create category" "200|201"
api GET "/license/certificate-types/$NEW/categories/test";       check "A20 GET category" 200
api DELETE "/license/certificate-types/$NEW/categories/test";    check "A21 deactivate category" "200|204"
api GET "/license/certificate-types?citizen=true";              check "A22 citizen list now includes $NEW" 200; echo "     visible to citizens: $(jq_ "'$NEW' in [t['code'] for t in d['certificateTypes']]")"
api DELETE "/license/certificate-types/$NEW";                    check "A23 delete type (live, nothing filed)" "200|204"

echo "## B. citizen — apply"
api GET /filestore/v3/document-categories; DOCMOD=$(jq_ '[x["type"] for x in d if x["code"]=="ID_CARD_OR_PASSPORT"][0]')
api GET "/schema/certificate/$CT.form/schema"; SCHEMA_ID=$(jq_ '[x for x in d if x.get("latestVersion") or x.get("isLatest")][0]["id"]'); echo "     doc module=$DOCMOD schemaDefinitionId=$SCHEMA_ID"
as citizen
api GET "/license/certificate-types?citizen=true";              check "B1 citizen sees live types" 200
api POST /individuals/v3/individuals "{\"givenName\":\"Citizen\",\"familyName\":\"Scenario\",\"mobileNumber\":\"+919800$STAMP\",\"gender\":\"OTHER\",\"email\":\"lnp-citizen@$USERDOM\"}"; check "B2 create own Individual (plural alias route)" "200|201"; IND=$(jq_ 'd.get("individualId") or d.get("id")'); echo "     individualId=$IND"
api POST "/license/certificate-types/$CT/drafts" "{\"currentStep\":\"details\",\"data\":{\"businessName\":\"Draft Traders\"}}"; check "B3 create draft" "200|201"; DRAFT=$(jq_ 'd.get("id") or d.get("draftId")')
api GET "/license/certificate-types/$CT/drafts";                 check "B4 list my drafts" 200
api GET "/license/drafts/$DRAFT";                                check "B5 resume draft" 200
api PUT "/license/drafts/$DRAFT" "{\"currentStep\":\"documents\",\"data\":{\"businessName\":\"Draft Traders 2\"}}"; check "B6 update draft" 200
api DELETE "/license/drafts/$DRAFT";                             check "B7 discard draft" "200|204"
upload ID_CARD_OR_PASSPORT "$DOCMOD";                            check "B8 upload document to filestore" "200|201"; echo "     fileStoreId=$FSID"
api POST "/license/certificate-types/$CT/certificates" "{\"applicantIds\":[\"$IND\"],\"holderSameAsApplicant\":true,\"holder\":{\"holderType\":\"INDIVIDUAL\"},\"addresses\":[{\"addressType\":\"PHYSICAL\",\"addressLines\":[\"1 Test Street\"],\"city\":\"Testville\",\"stateOrProvince\":\"TS\",\"postalCode\":\"500001\",\"country\":\"IN\"}],\"documents\":[{\"documentType\":\"ID_CARD_OR_PASSPORT\",\"fileStoreId\":\"$FSID\"}],\"declaration\":{\"declarationAccepted\":true,\"consentToDataSharing\":true},\"channel\":\"CITIZEN_PORTAL\",\"schemaDefinitionId\":\"$SCHEMA_ID\",\"mobileNumber\":\"+919800$STAMP\",\"partyDetails\":{\"$IND\":{\"name\":\"Citizen Scenario\",\"mobileNumber\":\"+919800$STAMP\",\"email\":\"lnp-citizen@$USERDOM\",\"role\":\"APPLICANT\"}},\"category\":\"food.restaurant.dinein\",\"certificateDetail\":{\"businessName\":\"Scenario Diner $STAMP\",\"ownershipType\":\"SOLE_PROPRIETOR\",\"businessRegistrationDate\":\"2024-01-15\",\"annualTurnover\":1500000,\"numberOfEmployees\":8}}"; check "B9 apply (OTP type -> PENDING_VERIFICATION)" "200|201"
APP=$(jq_ 'd.get("id")'); REF=$(jq_ '((d.get("pendingVerification") or {}).get("otp") or {}).get("referenceId")'); echo "     application id=$APP status=$(st_) otpRef=$REF"
BYPASS=$(sops_get 'cluster-configs.secrets.license-certificate.certificate-otp-bypass-code')
api POST "/license/certificates/$APP/_verify" "{\"otp\":{\"referenceId\":\"$REF\",\"code\":\"$BYPASS\"}}"; unset BYPASS; check "B10 verify with the OTP bypass code" 200; echo "     status=$(st_) appNo=$(jq_ 'd.get("applicationNumber")') wfState=$(wf_)"
APPNO=$(jq_ 'd.get("applicationNumber")')
api GET "/license/certificate-types/$CT/certificates/$APP";      check "B11 GET my application" 200; echo "     keys: $(jq_ 'sorted(d.keys())')"
tr_ "{\"processCode\":\"$CT\",\"action\":\"VERIFY_DOCUMENTS\",\"comment\":\"citizen must not\"}"; check "B15 role gating: citizen cannot VERIFY_DOCUMENTS" "403|400|401"
api POST "/calculator/calculation/v3/$CT/estimate" "{\"entityId\":\"$APP\",\"entityDetail\":{\"businessName\":\"Scenario Diner\",\"ownershipType\":\"SOLE_PROPRIETOR\",\"annualTurnover\":1500000,\"numberOfEmployees\":8},\"category\":\"food.restaurant.dinein\"}"; check "B12 fee estimate" 200; echo "     total=$(jq_ 'd.get("totalAmount")') lines=$(jq_ 'len(d.get("lineItems",[]))')"
api GET "/license/certificate-types/$CT/certificates/citizen";   check "B13 my applications (citizen-scoped list)" 200
api POST "/license/certificates/search" "{\"applicationNumber\":\"$APPNO\"}"; check "B14 cross-type search by application number" 200; echo "     found=$(jq_ 'd.get("totalCount") if isinstance(d,dict) else len(d)')"

echo "## C. employees — transitions"; as verifier
api GET "/workflow/v3/transition?processCode=$CT&limit=10";       check "C1 verifier inbox" 200; echo "     inbox items=$(jq_ 'len(d if isinstance(d,list) else d.get("data",d.get("transitions",[])))')"
api GET "/workflow/v3/transition/count?countType=total&processCode=$CT"; check "C2 inbox count (countType=total)" 200
api GET "/license/certificate-types/$CT/certificates/$APP";      check "C3 verifier opens the application" 200; echo "     state=$(wf_) nextActions=$(jq_ '[a.get("action") or a.get("code") or a for a in (d.get("nextActions") or (d.get("workflow") or {}).get("nextActions") or [])]')"
tr_ "{\"processCode\":\"$CT\",\"action\":\"VERIFY_DOCUMENTS\",\"comment\":\"docs ok\"}"; check "C4 VERIFY_DOCUMENTS (document_verifier)" 200; echo "     -> $(st_) / $(wf_)"
as inspector
tr_ "{\"processCode\":\"$CT\",\"action\":\"COMPLETE_INSPECTION\",\"comment\":\"inspected\",\"additionalDetails\":{\"inspectionChecklist\":{\"fireSafety\":\"PASS\",\"signage\":\"PASS\",\"hygiene\":\"PASS\"}}}"; check "C5 COMPLETE_INSPECTION (field_inspector, checklist)" 200; echo "     -> $(st_) / $(wf_) ${BODY:0:120}"
as approver
tr_ "{\"processCode\":\"$CT\",\"action\":\"ISSUE_LICENSE\",\"comment\":\"approved\"}"; check "C6 ISSUE_LICENSE (approver) -> PENDING_PAYMENT" 200; echo "     -> $(st_) / $(wf_)"
for i in 1 2 3 4 5 6; do sleep 5; api GET "/billing/v3/bills?consumerCodes=$APPNO"; BILL=$(jq_ '(d if isinstance(d,list) else d.get("bills",d.get("data",[])))[0]["id"]'); [ -n "$BILL" ] && break; done
check "C7 bill raised for the application (calculator -> billing)" 200; AMT=$(jq_ '(d if isinstance(d,list) else d.get("bills",d.get("data",[])))[0].get("totalAmount")'); echo "     billId=$BILL amount=$AMT"

echo "## D. payment"; as counter
api POST /billing/v3/payments "{\"totalAmountPaid\":${AMT:-0},\"paymentMode\":\"CASH\",\"paidBy\":\"Scenario Diner\",\"payerName\":\"Citizen Test\",\"paymentDetails\":[{\"totalAmountPaid\":${AMT:-0},\"billId\":\"$BILL\"}]}"; check "D1 counter payment (CASH) against the bill" "200|201"; echo "     payment status=$(jq_ 'd.get("paymentStatus")') txn=$(jq_ 'd.get("transactionNumber")')"
for i in 1 2 3 4 5 6 7 8; do sleep 10; as citizen; api GET "/license/certificate-types/$CT/certificates/$APP"; ST=$(wf_); [ "$ST" != "PENDING_PAYMENT" ] && break; done
if [ "$ST" = "PENDING_ISSUANCE" ]; then PASS=$((PASS+1)); echo "  PASS  D2 payment event moved the application to PENDING_ISSUANCE" | tee -a "$REPORT"
else FAIL=$((FAIL+1)); echo "  FAIL  D2 payment event did not advance the workflow (state=$ST)" | tee -a "$REPORT"; as counter; tr_ "{\"processCode\":\"$CT\",\"action\":\"PAY_LICENSE_FEE\",\"comment\":\"manual pay transition\"}"; check "D2b fallback: counter PAY_LICENSE_FEE transition" "200"; fi

echo "## E. issuance + lifecycle"; as approver
tr_ "{\"processCode\":\"$CT\",\"action\":\"ISSUE\",\"comment\":\"issue\"}"; check "E1 ISSUE (approver) -> terminal ISSUED" 200; echo "     status=$(st_) certNo=$(jq_ 'd.get("certificateNumber")')"
sleep 10; api GET "/license/certificate-types/$CT/certificates/$APP"; echo "     after issuance: status=$(st_) certNo=$(jq_ 'd.get("certificateNumber")') docTypes=$(jq_ '[x.get("documentType") for x in (d.get("documents") or [])]') credential=$(jq_ 'str(d.get("credential") or d.get("vc") or d.get("credentialCode") or "")[:80]')"
[ "$(st_)" = "APPROVED" ] && { PASS=$((PASS+1)); echo "  PASS  E1b issuance landed on APPROVED (VC + PDF done)" | tee -a "$REPORT"; } || { FAIL=$((FAIL+1)); echo "  FAIL  E1b status after issuance is $(st_) (expected APPROVED)" | tee -a "$REPORT"; }
as citizen; api GET "/license/certificates/documents?applicantId=$IND"; check "E2 My Documents (issued)" 200; echo "     issued=$(jq_ 'len((d.get("documents") or {}).get("ISSUED",[]))')"
api GET "/credential/$APPNO/jwt?credentialType=$CT";            check "E3 credential JWT for the application number" "200|404"
as_admin x "$2" "$3"
api POST "/license/certificate-types/$CT/certificates/$APP/suspend" "{\"reason\":\"scenario\"}"; check "E4 suspend" 200; echo "     $(st_)"
api POST "/license/certificate-types/$CT/certificates/$APP/reinstate" "{\"reason\":\"scenario\"}"; check "E5 reinstate" 200; echo "     $(st_)"
api POST "/license/certificate-types/$CT/certificates/$APP/revoke" "{\"reason\":\"scenario\"}"; check "E6 revoke" 200; echo "     $(st_)"
api POST "/license/certificates/search" "{\"status\":\"REVOKED\",\"certificateTypeCode\":\"$CT\"}"; check "E7 search REVOKED" 200; echo "     count=$(jq_ 'd.get("totalCount") if isinstance(d,dict) else len(d)')"

echo "## F. realm-policy proof (citizen token)"; as citizen
api GET /filestore/v3/document-categories;                      check "F1 citizen reads document categories" 200
api GET "/billing/v3/bills?consumerCodes=$APPNO";               check "F2 citizen reads own bill" 200
api GET "/billing/v3/business-services/$CT";                    check "F3 citizen reads business service" 200
api GET "/registry/v3/bankAccount/data/_registry";              check "F4 citizen passes rbac on registry _registry (400 = service-level, allowed through)" "200|400"
summary
