#!/bin/bash
# mint-tokens.sh <scripts-dir> <admin-email> <admin-capture> <users-env> <out.json> — citizen + verifier tokens and the tenant's OTP
# bypass code → secrets.json (mode 600) for core.js. Values are written to the file only, never printed. Tokens live 4 h.
set -uo pipefail; HERE=$(cd "$(dirname "$0")" && pwd); source "$HERE/../lib-api.sh" "$1" BASETENANT "$2" "$3"; USERS=$4; OUT=$5
set -a; . "$USERS"; set +a
tok() { printf '%s\n' "${!2}" > /tmp/.pw.$$; chmod 600 /tmp/.pw.$$; mint BASETENANT "$1" /tmp/.pw.$$ >/dev/null; rm -f /tmp/.pw.$$; cat "$TOKFILE"; }
umask 077
python3 - "$OUT" "$(tok "lnp-citizen@$DOMAIN" PW_citizen)" "$(tok "priya.verma@$DOMAIN" PW_verifier)" "$(sops_get 'cluster-configs.secrets.license-certificate.certificate-otp-bypass-code')" <<'PY'
import json,sys; json.dump({"citizen":sys.argv[2],"verifier":sys.argv[3],"otpBypass":sys.argv[4]}, open(sys.argv[1],"w"))
print("  secrets.json written:", all(len(x)>10 for x in sys.argv[2:4]), "(tokens present)", bool(sys.argv[4]), "(bypass present)")
PY
rm -f "$TOKFILE"; chmod 600 "$OUT"
