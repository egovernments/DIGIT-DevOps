#!/bin/bash
# mk-application.sh <scripts-dir> <admin-email> <admin-capture> <users-env> [type]  — files + OTP-verifies one application as the
# test citizen (API) and prints its application number. Used to give the employee UI something to act on.
# MK_USER / MK_PWVAR / MK_IND / MK_NAME / MK_MOBILE / MK_EMAIL in the environment file it for another citizen (see citizen-env.sh);
# MK_CATEGORY adds a category path (only for types whose categoryConfig is enabled — Business License's is off in this seed).
set -uo pipefail; HERE=$(cd "$(dirname "$0")" && pwd); source "$HERE/lib-api.sh" "$1" BASETENANT "$2" "$3"; source "$4"; CT=${5:-BUSINESS_LICENSE}; STAMP=$(date +%H%M%S)
mint BASETENANT "$2" "$3" >/dev/null
api GET /filestore/v3/document-categories; DOCMOD=$(jq_ '[x["type"] for x in d if x["code"]=="ID_CARD_OR_PASSPORT"][0]')
api GET "/schema/certificate/$CT.form/schema"; SCHEMA_ID=$(jq_ '[x for x in d if x.get("latestVersion") or x.get("isLatest")][0]["id"]')
PWVAR=${MK_PWVAR:-PW_citizen}; USER_=${MK_USER:-lnp-citizen@$DOMAIN}; MOB=${MK_MOBILE:-+919800$STAMP}; NAME=${MK_NAME:-Citizen Scenario}; MAIL=${MK_EMAIL:-lnp-citizen@$DOMAIN}
printf '%s\n' "${!PWVAR}" > /tmp/.pw.$$; chmod 600 /tmp/.pw.$$; mint BASETENANT "$USER_" /tmp/.pw.$$ >/dev/null; rm -f /tmp/.pw.$$
if [ -n "${MK_IND:-}" ]; then IND=$MK_IND; else
api POST /individuals/v3/individuals "{\"givenName\":\"Citizen\",\"familyName\":\"Scenario\",\"mobileNumber\":\"$MOB\",\"gender\":\"OTHER\",\"email\":\"$MAIL\"}"; IND=$(jq_ 'd.get("individualId") or d.get("id")'); fi
out=$(cat "$TOKFILE" | vm_ssh "read -r T; printf '%%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%%%EOF\n' > /tmp/lnp-doc.pdf; curl -s -m 60 -X POST 'http://$KGIP:8000/filestore/v3/files/upload?module=$DOCMOD&tag=ID_CARD_OR_PASSPORT' -H 'Host: $DOMAIN' -H 'X-Tenant-ID: $TENANT' -H 'X-User-Id: lnp-test' -H \"Authorization: Bearer \$T\" -F 'file=@/tmp/lnp-doc.pdf;type=application/pdf'"); FSID=$(printf '%s' "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d if isinstance(d,list) else d.get("files") or [d])[0].get("fileStoreId") or (d if isinstance(d,list) else [d])[0].get("id"))')
api POST "/license/certificate-types/$CT/certificates" "{\"applicantIds\":[\"$IND\"],\"holderSameAsApplicant\":true,\"holder\":{\"holderType\":\"INDIVIDUAL\"},\"addresses\":[{\"addressType\":\"PHYSICAL\",\"addressLines\":[\"1 Test Street\"],\"city\":\"Testville\",\"stateOrProvince\":\"TS\",\"postalCode\":\"500001\",\"country\":\"IN\"}],\"documents\":[{\"documentType\":\"ID_CARD_OR_PASSPORT\",\"fileStoreId\":\"$FSID\"}],\"declaration\":{\"declarationAccepted\":true,\"consentToDataSharing\":true},\"channel\":\"CITIZEN_PORTAL\",\"schemaDefinitionId\":\"$SCHEMA_ID\",\"mobileNumber\":\"$MOB\",\"partyDetails\":{\"$IND\":{\"name\":\"$NAME\",\"mobileNumber\":\"$MOB\",\"email\":\"$MAIL\",\"role\":\"APPLICANT\"}},${MK_CATEGORY:+\"category\":\"$MK_CATEGORY\",}\"certificateDetail\":{\"businessName\":\"UI Diner $STAMP\",\"ownershipType\":\"SOLE_PROPRIETOR\",\"businessRegistrationDate\":\"2024-01-15\",\"annualTurnover\":1500000,\"numberOfEmployees\":8}}"
APP=$(jq_ 'd.get("id")'); REF=$(jq_ '((d.get("pendingVerification") or {}).get("otp") or {}).get("referenceId")')
BYPASS=$(sops_get 'cluster-configs.secrets.license-certificate.certificate-otp-bypass-code'); api POST "/license/certificates/$APP/_verify" "{\"otp\":{\"referenceId\":\"$REF\",\"code\":\"$BYPASS\"}}"; unset BYPASS
echo "$(jq_ 'd.get("applicationNumber")')"; rm -f "$TOKFILE"
