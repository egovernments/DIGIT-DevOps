#!/bin/bash
# run-ladder.sh <base-url> <label> [steps="1 5 10 25 50 100"] [duration=10m] — on the generator: core.js at each VU step,
# results/<label>/core-<vus>.json summaries. Stop rule = error rate >= MAX_ERR (default 0.01, i.e. 1 %): the p95 thresholds in
# core.js stay in the report but no longer end the ladder (they are a latency SLO, the error rate is the breaking point).
set -uo pipefail; BASE=$1; LABEL=$2; STEPS=${3:-"1 5 10 25 50 100"}; DUR=${4:-10m}; HERE=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$HERE/results/$LABEL"
for v in $STEPS; do
  echo "== $LABEL core vus=$v $DUR $(date +%T)"
  BASE=$BASE VUS=$v DURATION=$DUR k6 run --quiet --summary-export "$HERE/results/$LABEL/core-$v.json" "$HERE/core.js" > "$HERE/results/$LABEL/core-$v.log" 2>&1; rc=$?
  python3 "$HERE/summarize.py" "$HERE/results/$LABEL/core-$v.json" "$v" | sed 's/^/   /'
  err=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['metrics']['http_req_failed']['value'])" "$HERE/results/$LABEL/core-$v.json" 2>/dev/null || echo 0)
  [ $rc -ne 0 ] && [ $rc -ne 99 ] && { echo "   k6 exit $rc at vus=$v — ladder stops"; break; }
  python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) >= float(sys.argv[2]) else 1)" "$err" "${MAX_ERR:-0.01}" && { echo "   error rate $err >= ${MAX_ERR:-0.01} at vus=$v — ladder stops"; break; }
  sleep 120   # queues drain between steps
done
