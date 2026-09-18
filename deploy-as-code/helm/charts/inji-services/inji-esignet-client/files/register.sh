#!/bin/sh
set -e

EP="$BASE/client-mgmt/oidc-client"

## eSignet's startup is slow (JVM + HSM key setup) and its
## readiness probe has a 180s initial delay, so this Job can
## easily start first. A connection error must never be read as
## "client absent" -- that is the only path that writes.
i=0
until curl -sf -o /dev/null --max-time 5 "$BASE/actuator/health"; do
  i=$((i+1))
  [ "$i" -ge 48 ] && { echo "FATAL: esignet not reachable at $BASE after 48 tries (240s)."; \
    echo "Check the SERVICE port (not containerPort) and that step 05 is Healthy."; exit 1; }
  sleep 5
done
echo "esignet reachable"

## IDEMPOTENCE GATE. The client-management API has no GET for a
## single client in this version, so existence is checked in the
## only place that is authoritative: whether eSignet will accept
## the POST. A duplicate returns a specific error code rather
## than creating anything, so a re-run is inherently safe -- but
## we still distinguish "already exists" from a real failure so
## the Job reports success on a second run instead of failing.
REQ_TIME=$(date -u +%Y-%m-%dT%H:%M:%S.000Z)
sed "s/__REQUEST_TIME__/$REQ_TIME/" /config/client.json > /tmp/req.json

CODE=$(curl -s -o /tmp/resp.json -w '%{http_code}' --max-time 30 \
         -X POST "$EP" \
         -H 'Content-Type: application/json' \
         --data @/tmp/req.json)
echo "POST $EP -> $CODE"
cat /tmp/resp.json; echo

## eSignet answers 200 with errors[] populated on failure, so the
## status code alone proves nothing -- the same envelope that made
## its health endpoint look healthy while every route was locked.
if grep -q '"errors":\[\]' /tmp/resp.json 2>/dev/null; then
  echo "client '$CLIENT_ID' registered"
  exit 0
fi
## Duplicate. VERIFIED against the running service by deleting the
## Job and letting ArgoCD re-run it -- eSignet answers:
##   {"response":null,
##    "errors":[{"errorCode":"duplicate_client_id",
##               "errorMessage":"duplicate_client_id"}]}
## and creates nothing. The exact code is matched first; the
## looser patterns remain as a fallback in case a future version
## renames it.
if grep -q '"errorCode":"duplicate_client_id"' /tmp/resp.json 2>/dev/null \
   || grep -qE 'duplicate|already[ _-]?exist' /tmp/resp.json 2>/dev/null; then
  echo "client '$CLIENT_ID' already registered -- leaving untouched (idempotent)"
  exit 0
fi
echo "registration failed"
exit 1
