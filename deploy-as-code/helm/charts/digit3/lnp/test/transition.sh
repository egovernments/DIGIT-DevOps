#!/bin/bash
# transition.sh <scripts-dir> <admin-email> <admin-capture> <users-env> <application-number> <ACTION>...  — drive one
# application through the workflow by API, each action as the role that owns it (verifier, inspector, approver, counter).
# Used to put an application into the state a UI check or demo segment starts from.
set -uo pipefail; HERE=$(cd "$(dirname "$0")" && pwd); source "$HERE/lib-api.sh" "$1" BASETENANT "$2" "$3"; set -a; source "$4"; set +a
APPNO=$5; shift 5; CT=${CT:-BUSINESS_LICENSE}
officer() { case $1 in verifier) echo priya.verma;; inspector) echo arjun.rao;; approver) echo meera.nair;; counter) echo ravi.kumar;; esac; }   # see mk-employees.sh
as() { local pw="PW_$1"; printf '%s\n' "${!pw}" > /tmp/.pw.$$; chmod 600 /tmp/.pw.$$; mint BASETENANT "$(officer "$1")@$DOMAIN" /tmp/.pw.$$ >/dev/null; rm -f /tmp/.pw.$$; }
as verifier; api POST "/license/certificates/search" "{\"applicationNumber\":\"$APPNO\"}"; APP=$(jq_ '(d.get("certificates") or d.get("results") or d)[0]["id"]')
[ -n "$APP" ] || { echo "  !! $APPNO not found"; rm -f "$TOKFILE"; exit 1; }
for ACTION in "$@"; do
  case "$ACTION" in
    VERIFY_DOCUMENTS)    as verifier;  body="{\"processCode\":\"$CT\",\"action\":\"$ACTION\",\"comment\":\"Documents verified.\"}" ;;
    COMPLETE_INSPECTION) as inspector; body="{\"processCode\":\"$CT\",\"action\":\"$ACTION\",\"comment\":\"Premises inspected.\",\"additionalDetails\":{\"inspectionChecklist\":{\"fireSafety\":\"PASS\",\"signage\":\"PASS\",\"hygiene\":\"PASS\"}}}" ;;
    ISSUE_LICENSE|ISSUE|REJECT) as approver; body="{\"processCode\":\"$CT\",\"action\":\"$ACTION\",\"comment\":\"$ACTION by API.\"}" ;;
    PAY_CASH)            as counter; sleep 5; api GET "/billing/v3/bills?consumerCode=$APPNO"
                         BILL=$(jq_ '[b for b in d if b.get("consumerCode")=="'"$APPNO"'"][0]["id"]'); AMT=$(jq_ '[b for b in d if b.get("consumerCode")=="'"$APPNO"'"][0]["totalAmount"]')
                         api POST /billing/v3/payments "{\"totalAmountPaid\":$AMT,\"paymentMode\":\"CASH\",\"paidBy\":\"Counter\",\"payerName\":\"Citizen\",\"paymentDetails\":[{\"totalAmountPaid\":$AMT,\"billId\":\"$BILL\"}]}"
                         echo "  PAY_CASH bill ${BILL:0:8} amount=$AMT -> HTTP $CODE"; continue ;;
    *) echo "  !! unknown action $ACTION"; continue ;;
  esac
  api POST "/license/certificate-types/$CT/certificates/$APP" "$body"; echo "  $ACTION -> HTTP $CODE status=$(jq_ 'd.get("status")')"
done
rm -f "$TOKFILE"
