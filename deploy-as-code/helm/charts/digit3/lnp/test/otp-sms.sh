#!/bin/bash
# otp-sms.sh <mobile-digits> — latest OTP code "sent" to <mobile> via the SMS echo sink (its log holds the request). Prints the code only.
set -uo pipefail; M=$1
for i in $(seq 1 15); do
  CODE=$(kubectl logs -n egov deploy/lnp-test-sms-sink --since=10m 2>/dev/null | grep -F "$M" | tail -1 | python3 -c 'import sys,re,urllib.parse as u; l=sys.stdin.read(); l=u.unquote_plus(l); m=re.findall(r"\b(\d{4,8})\b", re.sub(r"\+?91?'"$M"'","",l)); print(m[-1] if m else "")')
  [ -n "$CODE" ] && { echo "$CODE"; exit 0; }; sleep 2; done; exit 1
