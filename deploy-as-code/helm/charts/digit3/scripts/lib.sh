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

# sudo breaks everything downstream: the kubeconfig and scripts/.env end up
# root-owned and unreadable to the later (non-root) script runs.
[ "$(id -u)" -ne 0 ] || die "do not run these scripts with sudo — nothing here needs root on the workstation, and root-owned kubeconfig/.env files break the later phases"

# Parse "$@" into SHAPE_FLAG (--shape X anywhere) + POSARGS (everything else).
parse_args() {
  SHAPE_FLAG=""
  POSARGS=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --shape)   [ $# -ge 2 ] || die "--shape needs a value (single-container | domain-bundles | per-service)"; SHAPE_FLAG="$2"; shift 2 ;;
      --shape=*) SHAPE_FLAG="${1#--shape=}"; shift ;;
      --*)       die "unknown option: $1" ;;
      *)         POSARGS+=("$1"); shift ;;
    esac
  done
  [ -z "$SHAPE_FLAG" ] || shape_helmfile "$SHAPE_FLAG" >/dev/null   # validate early
}

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

# ── deployment shapes ────────────────────────────────────────────────────────
# single-container (default) | domain-bundles | per-service. Deploy exactly ONE
# shape at a time — they publish the same ingress context paths.
DEFAULT_SHAPE="single-container"
PUBLISHED_TAG="modulith-29bd3a4"   # multi-arch egovio images exist for every shape at this tag

# 06-deploy.sh persists SHAPE in .env; scripts fall back to the default.
current_shape() { echo "${SHAPE:-$DEFAULT_SHAPE}"; }

shape_helmfile() {
  case "$1" in
    single-container) echo "digit3services-single-container-helmfile.yaml" ;;
    domain-bundles)   echo "digit3services-domain-bundles-helmfile.yaml" ;;
    per-service)      echo "digit3services-per-service-helmfile.yaml" ;;
    *) die "unknown shape '$1' (single-container | domain-bundles | per-service)" ;;
  esac
}

shape_manifest() { # <digit3-path> <shape>
  case "$2" in
    domain-bundles) echo "$1/src/bundles/domain-split.package.yaml" ;;
    *)              echo "$1/src/bundles/dev-bundle.package.yaml" ;;
  esac
}

shape_bundles() {
  case "$1" in
    single-container) echo "dev-bundle" ;;
    domain-bundles)   echo "identity-bundle notification-bundle billing-bundle admin-bundle" ;;
    per-service)      echo "" ;;
  esac
}

# per-service shape: env-file block names (resolved chart names). Their images
# are pinned per block in azure-k3s.yaml (mixed registries/tags from the
# reference deployment) — NOT a uniform tag like the bundle shapes.
PER_SERVICE_BLOCKS="idgen template-config billing apportion url-shortener pg-service otp notification employee individual workflow registry filestore localization account boundary"

hub_has() { # <[namespace/]repo:tag> — anonymous Docker Hub check (default ns egovio)
  local ref="${1%%:*}" tag="${1##*:}" ns=egovio repo
  case "$ref" in */*) ns="${ref%%/*}"; repo="${ref##*/}" ;; *) repo="$ref" ;; esac
  curl -sf -o /dev/null "https://hub.docker.com/v2/repositories/$ns/$repo/tags/$tag" 2>/dev/null
}

# Print "block repo:tag" for each per-service app image pinned in the env file
# (repository defaults to the chart name when the block doesn't override it).
per_service_images() {
  python3 - "$ENV_FILE" $PER_SERVICE_BLOCKS <<'PYEOF'
import sys, yaml
doc = yaml.safe_load(open(sys.argv[1]))
for b in sys.argv[2:]:
    img = (doc.get(b) or {}).get("image") or {}
    print(b, f"{img.get('repository', b)}:{img.get('tag', 'MISSING-TAG')}")
PYEOF
}

set_env_var() { # persist KEY=VALUE into scripts/.env (idempotent)
  grep -q "^$1=" "$DOTENV" 2>/dev/null && sed_i "s|^$1=.*|$1=\"$2\"|" "$DOTENV" || echo "$1=\"$2\"" >> "$DOTENV"
}

# curl a ClusterIP URL from the VM (kubectl port-forward over the tunnel is
# unreliable for data transfer — see INSTALL.md).
vm_curl() { vm_ssh "curl -s $*"; }
