#!/bin/bash
# mk-employees.sh <scripts-dir> <admin-email> <admin-capture> <users-env>  — the four LnP test employees (verifier, inspector,
# approver, counter) through LnP's own _provision-employees, plus a Keycloak CITIZEN user for the API tests. Passwords are
# generated into <users-env> (mode 600) on first use and never printed. Idempotent: re-runs re-provision the same people.
set -uo pipefail; HERE=$(cd "$(dirname "$0")" && pwd); U=$4
[ -f "$U" ] || (umask 077; for r in verifier inspector approver counter citizen; do echo "PW_$r=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)Aa1"; done > "$U")
source "$HERE/lib-api.sh" "$1" BASETENANT "$2" "$3"; set -a; source "$U"; set +a
mint BASETENANT "$2" "$3" >/dev/null
# the four officers (demo identities; e-mail = Keycloak username): role → given/family name, mobile
emp() { printf '{"email":"%s@%s","mobileNumber":"%s","givenName":"%s","familyName":"%s","gender":"OTHER","password":"%s","roleNames":["%s"],"employeeType":"PERMANENT","department":"LICENSING","designation":"OFFICER","jurisdictions":[]}' "$1" "$DOMAIN" "$2" "$3" "$4" "$5" "$6"; }
api POST /license/tenants/BASETENANT/_provision-employees "{\"employees\":[$(emp priya.verma 9800000011 Priya Verma "$PW_verifier" document_verifier),$(emp arjun.rao 9800000012 Arjun Rao "$PW_inspector" field_inspector),$(emp meera.nair 9800000013 Meera Nair "$PW_approver" approver),$(emp ravi.kumar 9800000014 Ravi Kumar "$PW_counter" counter_employee)]}"
echo "  _provision-employees -> HTTP $CODE"; printf '%s' "$BODY" | python3 -c '
import sys,json
try: d=json.load(sys.stdin)
except Exception: raise SystemExit
for e in (d.get("employees") or d.get("results") or []): print("    %-32s %s" % (e.get("email"), str(e.get("status"))[:100]))' 2>/dev/null
rm -f "$TOKFILE"
# _provision-employees sets a temporary password (Keycloak asks for a new one at first login): make the test passwords final
for pair in verifier:priya.verma inspector:arjun.rao approver:meera.nair counter:ravi.kumar; do r=${pair%%:*}; bash "$HERE/mk-user.sh" "$1" BASETENANT "${pair#*:}@$DOMAIN" "PW_$r" "$U" 2>&1 | grep -E "clear required|set password" | sed "s/^/  $r: /"; done
bash "$HERE/mk-user.sh" "$1" BASETENANT "lnp-citizen@$DOMAIN" PW_citizen "$U" CITIZEN 2>&1 | sed 's/^/  citizen: /'
