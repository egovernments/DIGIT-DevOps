#!/bin/bash
# collect.sh <kubeconfig> <label> [interval=30] — on the laptop: pod CPU/memory, Postgres connections and Kafka lag every <interval> s
# → results/<label>/samples.csv while a ladder runs. Ctrl-C to stop.
set -uo pipefail; export KUBECONFIG=$1; LABEL=$2; INT=${3:-30}; HERE=$(cd "$(dirname "$0")" && pwd); mkdir -p "$HERE/results/$LABEL"; OUT="$HERE/results/$LABEL/samples.csv"
[ -s "$OUT" ] || echo "time,pod,cpu_m,mem_mi" > "$OUT"
while true; do t=$(date +%T); kubectl top pods -n egov --no-headers 2>/dev/null | awk -v t="$t" '{c=$2; m=$3; sub(/m/,"",c); sub(/Mi/,"",m); print t","$1","c","m}' >> "$OUT"
  pg=$(kubectl exec -n egov postgresql-lts-0 -- psql -U postgres -tAc "select count(*) from pg_stat_activity where state='active'" 2>/dev/null); echo "$t,postgres-active-connections,$pg," >> "$OUT"
  sleep "$INT"; done
