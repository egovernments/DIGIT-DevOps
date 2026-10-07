#!/bin/bash
# restore-after-load.sh <ssh-key> <vm-host> <notification-deploy> <scripts-dir> <admin-email> <admin-capture>
# Undo the load-test changes on a target VM: notification back to the real providers, test sinks deleted,
# Business License verification mode back to OTP. Run once the ladder, stability and recovery runs are done.
set -uo pipefail; KEY=$1; HOST=$2; DEP=$3; HERE=$(cd "$(dirname "$0")" && pwd)
ssh -i "$KEY" "azureuser@$HOST" "sudo k3s kubectl -n egov set env deploy/$DEP SMS_PROVIDER_URL=http://api.smscountry.com/SMSCwebservice_bulk.aspx SMTP_HOST=smtp.gmail.com SMTP_PORT=587 >/dev/null && sudo k3s kubectl -n egov rollout status deploy/$DEP --timeout=300s | tail -1; sudo k3s kubectl -n egov delete deploy,svc -l purpose=lnp-test 2>&1 | tail -4"
source "$HERE/../lib-api.sh" "$4" BASETENANT "$5" "$6"; mint BASETENANT "$5" "$6" >/dev/null
api GET /license/certificate-types/BUSINESS_LICENSE
api PUT /license/certificate-types/BUSINESS_LICENSE "$(jq_ 'json.dumps({**{k:v for k,v in d.items() if k not in ("auditDetail","dashboards","id","tenantId","configVersion","version")}, "submissionVerificationMode": "OTP"})')"
echo "  verification mode back to OTP -> HTTP $CODE"; rm -f "$TOKFILE"
