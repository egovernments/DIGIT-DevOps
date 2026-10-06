#!/bin/bash
# fetch-docs.sh <scripts-dir> <admin-email> <admin-capture> <application-number> <out-dir>  — download the documents the platform
# generated for one application (payment receipt, certificate) from the file store, via Kong, as the tenant admin.
# Writes <out-dir>/<DOCTYPE>.pdf (e.g. PAYMENT_RECEIPT.pdf, CERTIFICATE.pdf). Prints names and sizes only.
set -uo pipefail; HERE=$(cd "$(dirname "$0")" && pwd); source "$HERE/lib-api.sh" "$1" BASETENANT "$2" "$3"; APPNO=$4; DIR=$5; mkdir -p "$DIR"
mint BASETENANT "$2" "$3" >/dev/null
api POST "/license/certificates/search" "{\"applicationNumber\":\"$APPNO\"}"
APP=$(jq_ '(d.get("certificates") or d.get("results") or d)[0]["id"]'); CT=$(jq_ '(d.get("certificates") or d.get("results") or d)[0]["certificateTypeCode"]')
[ -n "$APP" ] || { echo "  !! $APPNO not found"; rm -f "$TOKFILE"; exit 1; }
api GET "/license/certificate-types/$CT/certificates/$APP"
# documents is {category: [docs]} (UPLOADED / GENERATED / ISSUED); take the receipt and the certificate
for pair in $(jq_ '" ".join((x.get("documentType") or "DOC")+":"+(x.get("fileStoreId") or "") for lst in ((d.get("documents") or {}).values() if isinstance(d.get("documents"), dict) else [d.get("documents") or []]) for x in lst if x.get("fileStoreId") and (x.get("documentType") or "") in ("PAYMENT_RECEIPT","CERTIFICATE"))'); do
  t=${pair%%:*}; id=${pair#*:}
  cat "$TOKFILE" | vm_ssh "read -r T; curl -s -m 60 -L 'http://$KGIP:8000/filestore/v3/files/$id' -H 'Host: $DOMAIN' -H 'X-Tenant-ID: $TENANT' -H 'X-User-Id: lnp-test' -H \"Authorization: Bearer \$T\" | base64 -w0" | base64 -d > "$DIR/$t.pdf"
  printf '  %-16s %s bytes  %s\n' "$t" "$(stat -c %s "$DIR/$t.pdf")" "$(head -c 5 "$DIR/$t.pdf" | tr -d '\n')"
done
rm -f "$TOKFILE"
