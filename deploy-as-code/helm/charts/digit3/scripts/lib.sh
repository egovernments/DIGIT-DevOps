#!/usr/bin/env bash
# Shared helpers for the numbered install scripts. Source, don't execute.
#
# Layout anchors (scripts/ lives beside deploy.sh in charts/digit3):
#   SCRIPT_DIR  charts/digit3/scripts     HELM_DIR   deploy-as-code/helm
#   CHART_DIR   charts/digit3             ENV_FILE / SECRETS_FILE  environments/*
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
CHART_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
HELM_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
ENV_FILE="$HELM_DIR/environments/azure-k3s.yaml"
SECRETS_FILE="$HELM_DIR/environments/azure-k3s-secrets.yaml"
DEPLOY="$CHART_DIR/deploy.sh"
DOTENV="$SCRIPT_DIR/.env"
TUNNEL_PORT=16443

die() { echo "ERROR: $*" >&2; exit 1; }
note() { echo "==> $*"; }
next() { echo; echo "next: $*"; }

# macOS sed needs -i '' ; GNU sed wants -i alone.
sed_i() {
  if sed --version >/dev/null 2>&1; then sed -i "$@"; else sed -i '' "$@"; fi
}

# Load scripts/.env (written by 01-cluster.sh) and export KUBECONFIG.
load_env() {
  [ -f "$DOTENV" ] || die "$DOTENV not found — run 01-cluster.sh <ssh-key> <domain> first"
  # shellcheck disable=SC1090
  source "$DOTENV"
  : "${SSH_KEY:?missing in .env}" "${DOMAIN:?missing in .env}" "${KUBECONFIG_PATH:?missing in .env}"
  VM_USER="${VM_USER:-azureuser}"
  export KUBECONFIG="$KUBECONFIG_PATH"
}

vm_ssh() { ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" "${VM_USER:-azureuser}@$DOMAIN" "$@"; }

# Re-open the API tunnel if the local port is closed.
ensure_tunnel() {
  if ! nc -z -w 2 127.0.0.1 "$TUNNEL_PORT" 2>/dev/null; then
    pkill -f "$TUNNEL_PORT:127.0.0.1:6443" 2>/dev/null || true
    ssh -f -N -L "$TUNNEL_PORT:127.0.0.1:6443" -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" "${VM_USER:-azureuser}@$DOMAIN"
    sleep 1
  fi
}

wait_for_pod() { # ns selector [timeout-seconds]
  local ns="$1" sel="$2" timeout="${3:-300}" waited=0
  until kubectl get pods -n "$ns" -l "$sel" --no-headers 2>/dev/null | grep -qE '1/1\s+Running'; do
    sleep 5; waited=$((waited + 5))
    [ "$waited" -ge "$timeout" ] && die "pod $ns/$sel not Ready after ${timeout}s: $(kubectl get pods -n "$ns" -l "$sel" --no-headers 2>&1 | head -2)"
  done
}

# Set one dotted path in the sops-encrypted secrets file without the value
# ever reaching a display, a file, or another process's argv.
sops_set() { # path value   (e.g. sops_set "vault-operator.root-token" "$TOKEN")
  SOPS_SET_PATH="$1" SOPS_SET_VALUE="$2" EDITOR="python3 $SCRIPT_DIR/_sops_set.py" \
    sops "$SECRETS_FILE" >/dev/null
}

sops_get() { # path (dotted) — prints the decrypted value to stdout
  local jq_path
  jq_path=$(python3 -c "import sys; print(''.join('[\"%s\"]' % p for p in sys.argv[1].split('.')))" "$1")
  sops -d --extract "$jq_path" "$SECRETS_FILE"
}

# Run a vault CLI command inside the pod, authenticated with the root token
# piped from the sops file (never displayed, never in argv).
vault_exec() { # 'vault subcommand ...'
  sops_get "vault-operator.root-token" | kubectl exec -i vault-0 -n vault -- \
    sh -c "read -r T; VAULT_TOKEN=\"\$T\" $*"
}

psql_exec() { kubectl exec -i -n egov postgresql-lts-0 -- psql -U postgres "$@"; }

# curl a ClusterIP URL from the VM (kubectl port-forward over the tunnel is
# unreliable for data transfer — see INSTALL.md).
vm_curl() { vm_ssh "curl -s $*"; }
