#!/bin/sh
set -e

TARGET="/keystore/${KEYSTORE_FILE}"

## IDEMPOTENCE. If a readable PKCS12 already exists, do nothing -- the
## keymanager will have added its own keys to it by then and regenerating
## would destroy every key Mimoto has issued.
if [ -f "$TARGET" ]; then
  if openssl pkcs12 -in "$TARGET" -nokeys -passin env:KEYSTORE_PASSWORD -info >/dev/null 2>&1; then
    echo "keystore already present and readable at $TARGET -- leaving untouched"
    exit 0
  fi
  echo "FATAL: $TARGET exists but is not a readable PKCS12 with the configured password."
  echo "Refusing to overwrite it. Inspect it manually -- overwriting would destroy"
  echo "any keys the keymanager has already stored."
  exit 1
fi

## A subPath mount creates a DIRECTORY when the target is missing, which is how
## this fails silently: the keymanager then sees a directory where it expects a
## PKCS12. Catch that explicitly.
if [ -d "$TARGET" ]; then
  echo "FATAL: $TARGET is a DIRECTORY."
  echo "Kubernetes created it because Mimoto mounted subPath=${KEYSTORE_FILE}"
  echo "before this keystore existed. Remove the directory and re-run:"
  echo "  kubectl -n <ns> delete pod -l app.kubernetes.io/name=mimoto"
  echo "  then delete this Job so ArgoCD recreates it"
  exit 1
fi

echo "generating $TARGET"
openssl req -x509 -newkey rsa:2048 -sha256 -days "${KEYSTORE_DAYS}" -nodes \
  -keyout /tmp/k.key -out /tmp/k.crt -subj "${KEYSTORE_SUBJECT}"

openssl pkcs12 -export \
  -inkey /tmp/k.key -in /tmp/k.crt \
  -name mimoto-keymanager \
  -out "$TARGET" \
  -passout env:KEYSTORE_PASSWORD

## Verify it is readable with the password Mimoto will use, so a broken
## keystore never reaches the service.
openssl pkcs12 -in "$TARGET" -nokeys -passin env:KEYSTORE_PASSWORD -info >/dev/null 2>&1 \
  || { echo "FATAL: generated keystore is not readable with the configured password"; exit 1; }

chmod 0644 "$TARGET"
echo "keystore created and verified: $(wc -c < "$TARGET") bytes"
