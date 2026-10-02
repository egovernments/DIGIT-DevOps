#!/bin/bash
# otp-mail.sh <recipient-email> — latest OTP code e-mailed to <recipient> (Mailpit test sink). Prints the code only.
set -uo pipefail; TO=$1
kubectl port-forward -n egov svc/lnp-test-mailpit 18025:8025 >/dev/null 2>&1 & PF=$!; trap 'kill $PF 2>/dev/null' EXIT; sleep 2
for i in $(seq 1 15); do
  ID=$(curl -s -m 5 "http://localhost:18025/api/v1/search?query=to:$TO&limit=1" | python3 -c 'import sys,json;d=json.load(sys.stdin);m=d.get("messages") or [];print(m[0]["ID"] if m else "")')
  if [ -n "$ID" ]; then curl -s -m 5 "http://localhost:18025/api/v1/message/$ID" | python3 -c 'import sys,json,re;d=json.load(sys.stdin);t=(d.get("Text") or "")+" "+re.sub("<[^>]+>"," ",d.get("HTML") or "");m=re.search(r"\b(\d{4,8})\b",t);print(m.group(1) if m else "")'; exit 0; fi; sleep 2; done; exit 1
