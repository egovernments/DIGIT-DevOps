#!/usr/bin/env bash
# Shared helpers for the numbered install scripts. Source, don't execute.
#
# Layout anchors (scripts/ lives beside deploy.sh in charts/digit3):
#   SCRIPT_DIR  charts/digit3/scripts     HELM_DIR   deploy-as-code/helm
#   CHART_DIR   charts/digit3             ENV_FILE / SECRETS_FILE  environments/*
set -euo pipefail
# Name the failing command: under set -e a step that suppresses its own output
# otherwise exits silently (seen: 04-vault dying right after "Sealed false"
# with nothing to show for it).
trap 'echo "ERROR: ${BASH_SOURCE[0]##*/}:${LINENO}: ${BASH_COMMAND} (exit $?)" >&2' ERR

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
  # per-environment secrets file when present (see deploy.sh) — sops_set/get
  # then read and write THIS environment's credentials, not another cluster's
  if [ -f "$HELM_DIR/environments/azure-k3s-secrets.$DOMAIN.yaml" ]; then
    SECRETS_FILE="$HELM_DIR/environments/azure-k3s-secrets.$DOMAIN.yaml"
  fi
  export KUBECONFIG="$KUBECONFIG_PATH"
}

vm_ssh() { ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" "${VM_USER:-azureuser}@$DOMAIN" "$@"; }

# Re-open the API tunnel if the local port is closed — or if the live tunnel
# points at a DIFFERENT domain: a workstation that drives several environments
# reuses the port, and a stale tunnel silently sends kubectl to the wrong
# cluster (the symptom is "x509: certificate signed by unknown authority").
ensure_tunnel() {
  if pgrep -f "$TUNNEL_PORT:127.0.0.1:6443" >/dev/null 2>&1 && \
     ! pgrep -af "$TUNNEL_PORT:127.0.0.1:6443" | grep -q "@$DOMAIN"; then
    note "tunnel on :$TUNNEL_PORT points at another environment — replacing it"
    pkill -f "$TUNNEL_PORT:127.0.0.1:6443" 2>/dev/null || true
    sleep 1
  fi
  # Liveness must be an END-TO-END probe, not a local port check: when a
  # forward dies the ssh process keeps holding the port, so `nc -z` succeeds
  # against a tunnel that forwards nothing and this function silently does
  # nothing while every kubectl call times out. Any HTTP status (401 included)
  # proves the far end answered; only "000" means no answer.
  if [ "$(curl -sk -m 5 -o /dev/null -w '%{http_code}' \
            "https://127.0.0.1:$TUNNEL_PORT/version" 2>/dev/null)" = "000" ]; then
    pkill -f "$TUNNEL_PORT:127.0.0.1:6443" 2>/dev/null || true
    # ExitOnForwardFailure: without it ssh only WARNS when the port is already
    # bound, exits 0 and backgrounds a useless duplicate while the old tunnel
    # keeps serving kubectl — make a busy port a hard failure instead.
    # ServerAlive*: without keepalives an idle or loaded forward is dropped by
    # the network with nothing noticing — the single most common cause of
    # "kubectl suddenly times out mid-phase" (INSTALL.md gotchas).
    ssh -f -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
      -o TCPKeepAlive=yes -L "$TUNNEL_PORT:127.0.0.1:6443" -o StrictHostKeyChecking=accept-new -i "$SSH_KEY" "${VM_USER:-azureuser}@$DOMAIN" \
      || die "could not open the tunnel on :$TUNNEL_PORT — port busy? run: pkill -f \"$TUNNEL_PORT:127.0.0.1:6443\" and retry"
    sleep 1
  fi
}

# Docker Hub credentials for authenticated pulls. Anonymous pulls are capped at
# 100/h per source IP and one per-service install needs 42 images, so a second
# install on the same VM within the hour hits 429. Read from the environment
# or from an untracked file; the images themselves stay public egovio/* — any
# Docker Hub account (read-only token) lifts the cap.
hub_creds() {
  if [ -z "${DOCKERHUB_TOKEN:-}" ] && [ -f "$HOME/.config/digit3/dockerhub.env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.config/digit3/dockerhub.env"
  fi
  [ -n "${DOCKERHUB_USER:-}" ] && [ -n "${DOCKERHUB_TOKEN:-}" ]
}

wait_for_pod() { # ns selector [timeout-seconds]
  local ns="$1" sel="$2" timeout="${3:-300}" waited=0
  until kubectl get pods -n "$ns" -l "$sel" --no-headers 2>/dev/null | grep -qE '1/1\s+Running'; do
    sleep 5; waited=$((waited + 5))
    # `if`, not `[ … ] && die`: the && list left status 1 as the loop's last
    # command whenever the pod was not Ready on the FIRST check, so the function
    # returned 1 and the caller's set -e killed the script (04-vault, twice).
    if [ "$waited" -ge "$timeout" ]; then
      die "pod $ns/$sel not Ready after ${timeout}s: $(kubectl get pods -n "$ns" -l "$sel" --no-headers 2>&1 | head -2)"
    fi
  done
  return 0
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
