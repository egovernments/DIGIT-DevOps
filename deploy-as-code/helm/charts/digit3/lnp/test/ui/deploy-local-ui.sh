#!/bin/bash
# Test-only: push locally built, per-VM UI images into the VM's containerd and point the four UI Deployments at them.
# The overlay keeps the published tags; a later `deploy.sh -f lnp-helmfile.yaml sync` reverts this.
#   deploy-local-ui.sh <scripts-dir> <tag>
set -uo pipefail; SCRIPTS=$1; TAG=$2; source "$SCRIPTS/lib.sh"; load_env; set +e; trap - ERR
for app in admin citizen employee validator; do
  docker --context desktop-linux image inspect egovio/license-$app:$TAG >/dev/null 2>&1 || { echo "  missing image egovio/license-$app:$TAG"; continue; }
  docker --context desktop-linux save egovio/license-$app:$TAG | vm_ssh 'sudo k3s ctr images import -' >/dev/null && echo "  imported license-$app:$TAG into the VM"
  kubectl set image deploy/license-$app -n egov license-$app=egovio/license-$app:$TAG >/dev/null && kubectl rollout status deploy/license-$app -n egov --timeout=180s | tail -1 | sed 's/^/  /'
done
