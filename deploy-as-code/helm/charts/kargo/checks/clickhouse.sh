#!/bin/sh
# ClickHouse functional check (digit3/analytics/clickhouse), run by Kargo verification
# after a promotion and on every "Reverify".
#
# Env:  NS               namespace of the ClickHouseCluster
#       TIMEOUT          seconds for the whole check
#       SETTLE_SECONDS   wait before checking, so Argo CD has applied the promoted chart
#                        (the ApplicationSet re-reads the env file every ~60s); the
#                        operator labels carry no chart version to wait on instead
#       READONLY_USER    user that must log in and be refused writes (default app)
#       USERS            further users that must log in (default otelcollector)
#       MIN_FREE_PCT     minimum free space on the data disk (default 15)
#
# Read-only. Logins run inside the server container with the passwords already in its
# environment (CLICKHOUSE_USER_<NAME>_PASSWORD, set by the chart from the Secret), so no
# Secret is read and nothing secret is printed. The only write attempted is one that
# must be refused.
set -u
TIMEOUT=${TIMEOUT:-600}
deadline=$(( $(date +%s) + TIMEOUT ))
RO=${READONLY_USER:-app}
USERS=${USERS:-otelcollector}
MIN_FREE=${MIN_FREE_PCT:-15}
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
left() { r=$(( deadline - $(date +%s) )); [ "$r" -lt 10 ] && r=10; echo "$r"; }

echo "== ClickHouse in namespace $NS"
[ "${SETTLE_SECONDS:-0}" -gt 0 ] && { echo "waiting ${SETTLE_SECONDS}s for Argo CD to apply the promoted chart"; sleep "$SETTLE_SECONDS"; }

# 1. Keeper and server StatefulSets exist and have rolled out.
for role in clickhouse-keeper clickhouse-server; do
  sts=""
  while [ -z "$sts" ] && [ "$(date +%s)" -lt "$deadline" ]; do
    sts=$(kubectl -n "$NS" get sts -l "clickhouse.com/role=$role" -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    [ -z "$sts" ] && sleep 10
  done
  [ -n "$sts" ] || { fail "no $role StatefulSet in $NS"; continue; }
  for s in $sts; do
    if kubectl -n "$NS" rollout status "sts/$s" --timeout="$(left)s" >/dev/null 2>&1; then pass "$role $s rolled out"; else fail "$role $s did not finish rolling out"; fi
  done
done
[ "$fails" -eq 0 ] || { echo "RESULT: $fails check(s) failed"; exit 1; }

pod=$(kubectl -n "$NS" get pod -l clickhouse.com/role=clickhouse-server -o jsonpath='{.items[0].metadata.name}')
cluster=$(kubectl -n "$NS" get pod "$pod" -o jsonpath='{.metadata.labels.clickhouse\.com/cluster}')
svc="$cluster-clickhouse-headless.$NS.svc.cluster.local"

# 2. Inside the server container (script on stdin; a function keeps the here-document
#    out of $(...), where shells mis-parse its case patterns).
inpod() { cat <<'SH'
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; }
pw() { eval "printf %s \"\${CLICKHOUSE_USER_$(echo "$1" | tr 'a-z-' 'A-Z_')_PASSWORD:-}\""; }
q() { u=$1; shift; clickhouse-client --user "$u" --password "$(pw "$u")" --query "$*" 2>&1; }

# logins
for u in $RO $USERS; do
  r=$(q "$u" "SELECT currentUser()")
  [ "$r" = "$u" ] && pass "user $u logs in with its password from the Secret" || fail "user $u login: $(echo "$r" | head -1 | cut -c1-160)"
done
r=$(clickhouse-client --user default --password '' --query "SELECT 1" 2>&1)
case "$r" in *AUTHENTICATION_FAILED*|*"Code: 516"*|*REQUIRED_PASSWORD*) pass "default user refuses an empty password";;
  *) fail "default user without a password: $(echo "$r" | head -1 | cut -c1-160)";; esac
r=$(clickhouse-client --user "$RO" --password "wrong-$(date +%s)" --query "SELECT 1" 2>&1)
case "$r" in *AUTHENTICATION_FAILED*|*"Code: 516"*) pass "user $RO refuses a wrong password";; *) fail "user $RO with a wrong password: $(echo "$r" | head -1 | cut -c1-160)";; esac

# permissions of the read-only user (what Superset connects as)
r=$(q "$RO" "SELECT count() FROM system.one")
[ "$r" = "1" ] && pass "user $RO can SELECT" || fail "user $RO SELECT: $(echo "$r" | head -1 | cut -c1-160)"
r=$(q "$RO" "CREATE TABLE default.__kargo_verify_should_fail (x UInt8) ENGINE = Memory")
case "$r" in *ACCESS_DENIED*|*"Code: 497"*) pass "user $RO is refused CREATE TABLE (read-only)";;
  *) fail "user $RO was NOT refused CREATE TABLE: $(echo "$r" | head -1 | cut -c1-160)";; esac

# Keeper reachable from the server
r=$(q "$RO" "SELECT count() FROM system.zookeeper WHERE path = '/'")
case "$r" in ''|*[!0-9]*) fail "Keeper not reachable: $(echo "$r" | head -1 | cut -c1-160)";; *) pass "Keeper reachable ($r znodes under /)";; esac

# HTTP interface through the client Service (what Superset uses)
r=$(wget -qO- -T 10 "http://$SVC:8123/ping" 2>&1)
[ "$r" = "Ok." ] && pass "HTTP http://$SVC:8123/ping -> Ok." || fail "HTTP $SVC:8123/ping -> $r"

# system log tables have a TTL (unified-dev filled its disk with an unbounded text_log)
r=$(q "$RO" "SELECT groupArray(name) FROM system.tables WHERE database = 'system' AND name LIKE '%_log' AND engine LIKE '%MergeTree' AND engine_full NOT LIKE '% TTL %'")
[ "$r" = "[]" ] && pass "every system *_log table has a TTL" || fail "system log tables without TTL: $r"

# disk headroom
r=$(q "$RO" "SELECT toUInt8(100 * free_space / total_space) FROM system.disks WHERE name = 'default'")
case "$r" in ''|*[!0-9]*) fail "disk free: $r";;
  *) [ "$r" -ge "$MIN_FREE" ] && pass "data disk ${r}% free (minimum ${MIN_FREE}%)" || fail "data disk only ${r}% free (minimum ${MIN_FREE}%)";; esac

r=$(q "$RO" "SELECT version()")
echo "INFO: ClickHouse $r"
SH
}
out=$(inpod | kubectl -n "$NS" exec -i "$pod" -c clickhouse-server -- \
  env RO="$RO" USERS="$USERS" MIN_FREE="$MIN_FREE" SVC="$svc" sh -s 2>&1)
echo "$out"
fails=$(( fails + $(echo "$out" | grep -c '^FAIL:') ))
echo "$out" | grep -q '^PASS: user ' || fail "the in-pod checks did not run"

if [ "$fails" -eq 0 ]; then echo "RESULT: ClickHouse is configured and ready to use"; exit 0; fi
echo "RESULT: $fails check(s) failed"; exit 1
