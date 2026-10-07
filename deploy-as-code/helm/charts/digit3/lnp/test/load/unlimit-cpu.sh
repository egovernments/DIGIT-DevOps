#!/bin/bash
# unlimit-cpu.sh <ssh-key> <vm-host> <target>... — load-test mode on a target VM: drop the CPU LIMITS (CFS throttling
# distorts latency and caps throughput below what the node can give) and lower the CPU REQUESTS so rolling updates can
# schedule next to the running pod. Memory requests and limits are left as they are. One rollout at a time.
# <target> = name (an egov Deployment) or namespace/kind/name, e.g. egov/statefulset/postgresql-lts, keycloak/deploy/keycloak.
# Before: results/<label>/resources-before.txt (see README). Reverse with `helmfile sync` of the shape (chart values).
set -uo pipefail
KEY=$1; HOST=$2; shift 2
[ $# -gt 0 ] || { echo "usage: $0 <ssh-key> <vm-host> <target>..."; exit 2; }
# the remote script is fed on stdin to `bash -s`, which makes the targets its positional parameters
ssh -o ConnectTimeout=15 -i "$KEY" "azureuser@$HOST" bash -s -- "$@" <<'REMOTE'
set -u
patch() {
  ns=$1; kind=$2; d=$3; req=$4; K="sudo k3s kubectl -n $ns"
  $K patch "$kind" "$d" --type=json -p "[{\"op\":\"remove\",\"path\":\"/spec/template/spec/containers/0/resources/limits/cpu\"},{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/requests/cpu\",\"value\":\"$req\"}]" >/dev/null 2>&1 \
    || $K patch "$kind" "$d" --type=json -p "[{\"op\":\"replace\",\"path\":\"/spec/template/spec/containers/0/resources/requests/cpu\",\"value\":\"$req\"}]" >/dev/null
  sel=$($K get "$kind" "$d" -o jsonpath='{.spec.selector.matchLabels}' | python3 -c 'import sys,json; print(",".join(f"{k}={v}" for k,v in json.load(sys.stdin).items()))')
  for i in $(seq 1 30); do
    $K rollout status "$kind/$d" --timeout=20s >/dev/null 2>&1 && { echo "  $ns/$kind/$d: rolled out (requests cpu=$req, no cpu limit)"; return; }
    pend=$($K get pods -l "$sel" --field-selector=status.phase=Pending -o name 2>/dev/null | head -1)
    old=$($K get pods -l "$sel" --field-selector=status.phase=Running -o name 2>/dev/null | head -1)
    if [ "$kind" = deploy ] && [ -n "$pend" ] && [ -n "$old" ] && [ "$i" -ge 3 ]; then echo "  $d: new pod pending (no room beside the old one) — retiring $old"; $K delete "$old" --wait=false >/dev/null; fi
  done
  echo "  !! $ns/$kind/$d: rollout did not finish in 10 min — check: $K get pods -l $sel"
}
echo "== patching: $*"
for t in "$@"; do
  case $t in */*/*) ns=${t%%/*}; rest=${t#*/}; kind=${rest%%/*}; d=${rest#*/} ;; *) ns=egov; kind=deploy; d=$t ;; esac
  case $d in
    *-bundle|dev-bundle|account|individual|employee|boundary|workflow|billing|apportion|pg-service|idgen|filestore|notification|otp|localization|template-config|url-shortener|registry|postgresql-lts|keycloak) patch "$ns" "$kind" "$d" 200m ;;
    *) patch "$ns" "$kind" "$d" 50m ;;
  esac
done
echo "== node allocation now:"; sudo k3s kubectl describe node | sed -n "/Allocated resources/,/Events/p" | grep -E "cpu|memory"
echo "== cpu limits left on the application path (all namespaces):"
for ns in egov backbone keycloak; do sudo k3s kubectl -n $ns get deploy,statefulset -o custom-columns=NS:.metadata.namespace,NAME:.metadata.name,LIM_CPU:.spec.template.spec.containers[0].resources.limits.cpu --no-headers 2>/dev/null; done \
  | grep -vE "<none>|cert-manager|lnp-test|license-(admin|citizen|employee|validator)|ingress|vault" || echo "  none"
REMOTE
