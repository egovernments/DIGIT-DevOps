#!/bin/sh
# ClickHouse operator check (digit3/analytics/clickhouse-operator), run by Kargo
# verification after a promotion and on every "Reverify".
#
# Env:  NS               namespace of the operator
#       TIMEOUT          seconds for the whole check
#       SETTLE_SECONDS   wait before checking, so Argo CD has applied the promoted chart
#       STABLE_SECONDS   the manager must stay up this long with no restart (default 60)
#
# Read-only: Deployments, Pods, Endpoints and the manager's log.
set -u
TIMEOUT=${TIMEOUT:-600}
STABLE=${STABLE_SECONDS:-60}
deadline=$(( $(date +%s) + TIMEOUT ))
fails=0
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*"; fails=$((fails + 1)); }
left() { r=$(( deadline - $(date +%s) )); [ "$r" -lt 10 ] && r=10; echo "$r"; }

echo "== ClickHouse operator in namespace $NS"
[ "${SETTLE_SECONDS:-0}" -gt 0 ] && { echo "waiting ${SETTLE_SECONDS}s for Argo CD to apply the promoted chart"; sleep "$SETTLE_SECONDS"; }

d=""
while [ -z "$d" ] && [ "$(date +%s)" -lt "$deadline" ]; do
  d=$(kubectl -n "$NS" get deploy -l control-plane=controller-manager -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
  [ -z "$d" ] && sleep 10
done
[ -n "$d" ] || { echo "FAIL: no operator Deployment in $NS"; exit 1; }

if kubectl -n "$NS" rollout status "deploy/$d" --timeout="$(left)s" >/dev/null 2>&1; then
  pass "$d rolled out ($(kubectl -n "$NS" get deploy "$d" -o jsonpath='{.spec.template.spec.containers[0].image}'))"
else
  fail "$d did not finish rolling out"; echo "RESULT: $fails check(s) failed"; exit 1
fi

restarts() { kubectl -n "$NS" get pods -l control-plane=controller-manager -o jsonpath='{range .items[*]}{range .status.containerStatuses[*]}{.restartCount}{" "}{end}{end}' | awk '{s=0; for(i=1;i<=NF;i++) s+=$i; print s}'; }
r0=$(restarts); sleep "$STABLE"; r1=$(restarts)
[ "$r0" = "$r1" ] && pass "manager stable for ${STABLE}s (restarts $r1)" || fail "manager restarted while checking ($r0 -> $r1)"

# The admission webhook must have a ready backend, or every ClickHouseCluster/KeeperCluster
# create/update is rejected.
for s in $(kubectl -n "$NS" get svc -o jsonpath='{.items[*].metadata.name}'); do
  case "$s" in *webhook*)
    a=$(kubectl -n "$NS" get endpoints "$s" -o jsonpath='{.subsets[*].addresses[*].ip}')
    [ -n "$a" ] && pass "webhook Service $s has ready endpoints" || fail "webhook Service $s has no ready endpoints";;
  esac
done

e=$(kubectl -n "$NS" logs "deploy/$d" --since=10m 2>/dev/null | grep -c '"level":"error"')
[ "$e" -eq 0 ] && pass "no errors in the manager log in the last 10 minutes" || echo "WARN: $e error line(s) in the manager log in the last 10 minutes"

if [ "$fails" -eq 0 ]; then echo "RESULT: ClickHouse operator is ready"; exit 0; fi
echo "RESULT: $fails check(s) failed"; exit 1
