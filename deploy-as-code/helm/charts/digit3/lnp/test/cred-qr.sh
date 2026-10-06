#!/bin/bash
# cred-qr.sh <scripts-dir> <admin-email> <admin-capture> <application-number> <out.png>  — the issued credential's JWT
# (vc service, through Kong) rendered as the QR a holder would present; the validator app scans or uploads it.
set -uo pipefail; HERE=$(cd "$(dirname "$0")" && pwd); source "$HERE/lib-api.sh" "$1" BASETENANT "$2" "$3"; APPNO=$4; OUTPNG=$5
mint BASETENANT "$2" "$3" >/dev/null
for _ in 1 2 3 4 5 6; do api GET "/credential/$APPNO/jwt"; JWT=$(jq_ 'd.get("jwt") or d.get("token") or ""'); [ -n "$JWT" ] && break; sleep 5; done
rm -f "$TOKFILE"; [ -n "$JWT" ] || { echo "  !! no credential JWT for $APPNO (HTTP $CODE)"; exit 1; }
if command -v qrencode >/dev/null; then printf '%s' "$JWT" | qrencode -o "$OUTPNG" -s 6 -l M
else python3 -c 'import qrcode,sys; qrcode.make(sys.argv[1]).save(sys.argv[2])' "$JWT" "$OUTPNG"; fi
unset JWT; echo "  credential QR for $APPNO -> $OUTPNG"
