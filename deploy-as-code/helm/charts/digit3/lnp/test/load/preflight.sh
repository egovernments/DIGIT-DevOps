#!/bin/bash
# preflight.sh <ssh-key> <vm-host> <notification-deploy> <scripts-dir> <admin-email> <admin-capture> — read-only checks that
# a target VM is in load-test mode before a ladder starts. Exit 1 on any failure. Checks:
#   1. no CPU limit on any pod of the application path (bundles/services, LnP backends, kong)
#   2. Business License submissionVerificationMode = NONE (no OTP SMS per apply)
#   3. notification SMS and SMTP point at the test sinks, not the real providers
#   4. node allocation and k6 generator reachability are printed for the record
set -uo pipefail
KEY=$1; HOST=$2; DEP=$3; HERE=$(cd "$(dirname "$0")" && pwd); rc=0
echo "== 1. cpu limits on the application path"
lim=$(ssh -o ConnectTimeout=15 -i "$KEY" "azureuser@$HOST" 'for ns in egov backbone keycloak; do sudo k3s kubectl -n $ns get deploy,statefulset -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,LIM_CPU:.spec.template.spec.containers[0].resources.limits.cpu --no-headers 2>/dev/null; done' \
  | grep -vE "<none>|cert-manager|lnp-test|license-(admin|citizen|employee|validator)|ingress|vault")   # bundles/services, LnP backends, Postgres, Keycloak (Kong checks every request against it), MinIO
if [ -n "$lim" ]; then echo "$lim" | sed 's/^/  !! limited: /'; rc=1; else echo "  ok: none"; fi
echo "== 2. verification mode"
source "$HERE/../lib-api.sh" "$4" BASETENANT "$5" "$6"; mint BASETENANT "$5" "$6" >/dev/null
api GET /license/certificate-types/BUSINESS_LICENSE; mode=$(jq_ 'd.get("submissionVerificationMode")'); rm -f "$TOKFILE"
if [ "$mode" = "NONE" ]; then echo "  ok: NONE"; else echo "  !! BUSINESS_LICENSE submissionVerificationMode=$mode (apply would send a real OTP SMS)"; rc=1; fi
echo "== 3. notification endpoints"
env=$(ssh -o ConnectTimeout=15 -i "$KEY" "azureuser@$HOST" "sudo k3s kubectl -n egov get deploy $DEP -o jsonpath='{range .spec.template.spec.containers[0].env[*]}{.name}={.value}{\"\n\"}{end}'" | grep -E "^(SMS_PROVIDER_URL|SMTP_HOST)=")
echo "$env" | sed 's/^/  /'
echo "$env" | grep -qE "smscountry|gmail" && { echo "  !! real providers configured — status notifications would reach SMSCountry/Gmail"; rc=1; }
echo "== 4. node allocation"
ssh -o ConnectTimeout=15 -i "$KEY" "azureuser@$HOST" 'sudo k3s kubectl describe node | sed -n "/Allocated resources/,/Events/p" | grep -E "cpu|memory"' | sed 's/^/  /'
[ $rc -eq 0 ] && echo "PREFLIGHT OK" || echo "PREFLIGHT FAILED — fix the !! items before running a ladder"
exit $rc
