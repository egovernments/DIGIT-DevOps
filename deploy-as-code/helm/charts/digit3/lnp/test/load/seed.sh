#!/bin/bash
# seed.sh <scripts-dir> <admin-email> <admin-capture> <count> <out.json> — pre-create <count> citizens (individuals) for the load test,
# upload one ID document, read the form schema id → seed.json for core.js. Runs on the laptop via lib-api (not on the generator).
set -uo pipefail; HERE=$(cd "$(dirname "$0")" && pwd); source "$HERE/../lib-api.sh" "$1" BASETENANT "$2" "$3"; N=$4; OUT=$5; CT=${CT:-BUSINESS_LICENSE}
mint BASETENANT "$2" "$3" >/dev/null
api GET "/schema/certificate/$CT.form/schema"; SCHEMA=$(jq_ '[x for x in d if x.get("latestVersion") or x.get("isLatest")][0]["id"]')
api GET /filestore/v3/document-categories; DOCMOD=$(jq_ '[x["type"] for x in d if x["code"]=="ID_CARD_OR_PASSPORT"][0]')
# one tiny PDF as the applicant's ID document (same upload the application helper uses); reused by every lifecycle
out=$(cat "$TOKFILE" | vm_ssh "read -r T; printf '%%PDF-1.4\n1 0 obj<<>>endobj\ntrailer<<>>\n%%%%EOF\n' > /tmp/lnp-load-doc.pdf; curl -s -m 60 -X POST 'http://$KGIP:8000/filestore/v3/files/upload?module=$DOCMOD&tag=ID_CARD_OR_PASSPORT' -H 'Host: $DOMAIN' -H 'X-Tenant-ID: $TENANT' -H 'X-User-Id: lnp-load' -H \"Authorization: Bearer \$T\" -F 'file=@/tmp/lnp-load-doc.pdf;type=application/pdf'")
FSID=$(printf '%s' "$out" | python3 -c 'import sys,json; d=json.load(sys.stdin); print((d if isinstance(d,list) else d.get("files") or [d])[0].get("fileStoreId") or "")' 2>/dev/null)
[ -n "$FSID" ] || { echo "  !! upload returned no fileStoreId; response: $(printf '%s' "$out" | head -c 300)"; }
echo "  schema=$SCHEMA fileStoreId=$FSID"
STAMP=$(date +%s | tail -c 6)
# count 0 = refresh the document (and schema id) only: keep the individuals already in <out.json>; never blank a working fileStoreId
python3 - "$OUT" "$SCHEMA" "$FSID" "$N" <<'PY'
import json, os, sys
out, schema, fsid, n = sys.argv[1], sys.argv[2], sys.argv[3], int(sys.argv[4])
d = json.load(open(out)) if (n == 0 and os.path.exists(out)) else {"individuals": []}
if schema: d["schemaDefinitionId"] = schema
if fsid: d["fileStoreId"] = fsid
elif not d.get("fileStoreId"): d["fileStoreId"] = ""
json.dump(d, open(out, "w"))
PY
for i in $(seq 1 "$N"); do
  MOB="+9198$(printf '%05d%03d' "$STAMP" "$i" | tail -c 8)"; NAME="Load Citizen"      # names: letters and spaces only (API rule); mobile is the unique key
  api POST /individuals/v3/individuals "{\"givenName\":\"Load\",\"familyName\":\"Citizen\",\"mobileNumber\":\"$MOB\",\"gender\":\"OTHER\",\"email\":\"load$i@example.org\"}"
  ID=$(jq_ 'd.get("individualId") or d.get("id") or ""'); [ -n "$ID" ] || { echo "  !! individual $i failed HTTP $CODE: $(echo "$BODY" | head -c 160)"; continue; }   # jq_ prints Python None as the string "None"
  python3 - "$OUT" "$ID" "$MOB" "$NAME" <<'PY'
import json,sys; f=sys.argv[1]; d=json.load(open(f)); d["individuals"].append({"id":sys.argv[2],"mobile":sys.argv[3],"name":sys.argv[4]}); json.dump(d,open(f,"w"))
PY
done
rm -f "$TOKFILE"; echo "  seeded $(python3 -c "import json; print(len(json.load(open('$OUT'))['individuals']))") individuals → $OUT"
