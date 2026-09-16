#!/usr/bin/env bash
# 01 — k3s on the VM + kubeconfig over an SSH tunnel (INSTALL.md §1.2–1.3).
# Usage: ./01-cluster.sh <ssh-private-key> <domain> [vm-user]
# Idempotent: skips the k3s install if present, re-opens the tunnel if stale.
source "$(dirname "$0")/lib.sh"

[ $# -ge 2 ] || die "usage: $0 <ssh-private-key> <domain> [vm-user (default azureuser)]"
SSH_KEY="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
DOMAIN="$2"
VM_USER="${3:-azureuser}"
KUBECONFIG_PATH="$HOME/modulith-kubeconfig.yaml"
[ -f "$SSH_KEY" ] || die "ssh key not found: $SSH_KEY"

note "installing k3s (skipped if already installed)"
vm_ssh 'command -v k3s >/dev/null || curl -sfL https://get.k3s.io | sh -s - --disable traefik'
vm_ssh 'sudo k3s kubectl wait --for=condition=Ready node --all --timeout=180s' >/dev/null

note "opening SSH tunnel on 127.0.0.1:$TUNNEL_PORT"
ensure_tunnel

note "writing kubeconfig to $KUBECONFIG_PATH (server pointed at the tunnel port)"
vm_ssh 'sudo cat /etc/rancher/k3s/k3s.yaml' > "$KUBECONFIG_PATH"
sed_i "s|server: https://127.0.0.1:6443|server: https://127.0.0.1:$TUNNEL_PORT|" "$KUBECONFIG_PATH"
chmod 600 "$KUBECONFIG_PATH"

cat > "$DOTENV" <<EOF
SSH_KEY="$SSH_KEY"
DOMAIN="$DOMAIN"
VM_USER="$VM_USER"
KUBECONFIG_PATH="$KUBECONFIG_PATH"
EOF
note "saved connection settings to scripts/.env"

export KUBECONFIG="$KUBECONFIG_PATH"
kubectl get nodes

echo
echo "for manual kubectl use:  export KUBECONFIG=$KUBECONFIG_PATH"
next "./02-secrets.sh"
