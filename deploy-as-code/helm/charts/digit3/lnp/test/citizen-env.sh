#!/bin/bash
# citizen-env.sh <scripts-dir> <admin-email> <admin-capture> <users-env> <mobile e.g. +91...>  — make a citizen who registered
# through the UI usable from the API tests: a password (PW_mobilecitizen in <users-env>, generated once, never printed) on
# their Keycloak user (username = mobile number) and their individual id. Prints MK_* lines for mk-application.sh.
set -uo pipefail; HERE=$(cd "$(dirname "$0")" && pwd); U=$4; MOBILE=$5
grep -q '^PW_mobilecitizen=' "$U" 2>/dev/null || echo "PW_mobilecitizen=$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-16)Aa1" >> "$U"
bash "$HERE/mk-user.sh" "$1" BASETENANT "$MOBILE" PW_mobilecitizen "$U" CITIZEN 2>&1 | grep -E "set password|create user" | sed 's/^/  /'
source "$HERE/lib-api.sh" "$1" BASETENANT "$2" "$3"; mint BASETENANT "$2" "$3" >/dev/null
api GET "/individuals/v3/individuals?mobileNumber=$(printf %s "$MOBILE" | sed 's/+/%2B/')&limit=5"
IND=$(jq_ '[i for i in (d if isinstance(d,list) else d.get("individuals") or d.get("data") or []) if i.get("mobileNumber","").endswith("'"${MOBILE: -10}"'")][0].get("individualId") or [i for i in (d if isinstance(d,list) else d.get("individuals") or [])][0].get("id")')
NAME=$(jq_ '(lambda i: " ".join(x for x in (i.get("givenName"), i.get("familyName")) if x))([i for i in (d if isinstance(d,list) else d.get("individuals") or [])][0])')
EMAIL=$(jq_ '[i for i in (d if isinstance(d,list) else d.get("individuals") or [])][0].get("email") or ""')
rm -f "$TOKFILE"
[ -n "$IND" ] || { echo "  !! no individual found for $MOBILE"; exit 1; }
printf 'MK_USER=%q\nMK_PWVAR=PW_mobilecitizen\nMK_IND=%q\nMK_NAME=%q\nMK_MOBILE=%q\nMK_EMAIL=%q\n' "$MOBILE" "$IND" "${NAME:-Citizen}" "$MOBILE" "$EMAIL"
