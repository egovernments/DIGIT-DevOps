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

# Authenticated Docker Hub pulls: containerd on the VM does the pulling, so the
# credentials must live there — /etc/rancher/k3s/registries.yaml, read by k3s
# at start (k3s-uninstall removes it, hence written on every run, BEFORE the
# install). The token travels over stdin, never argv. Anonymous = 100 pulls/h
# per VM IP; a per-service install needs 42.
if hub_creds; then
  note "docker hub pulls authenticated as '$DOCKERHUB_USER' (registries.yaml on the VM)"
  printf '%s\n%s\n' "$DOCKERHUB_USER" "$DOCKERHUB_TOKEN" | vm_ssh 'read -r U; read -r P
    sudo mkdir -p /etc/rancher/k3s
    printf "configs:\n  \"docker.io\":\n    auth:\n      username: %s\n      password: %s\n  \"registry-1.docker.io\":\n    auth:\n      username: %s\n      password: %s\n" "$U" "$P" "$U" "$P" | sudo tee /etc/rancher/k3s/registries.yaml >/dev/null
    sudo chmod 600 /etc/rancher/k3s/registries.yaml
    if systemctl is-active --quiet k3s; then sudo systemctl restart k3s; fi'
else
  note "docker hub pulls are ANONYMOUS (100/h per VM IP) — set DOCKERHUB_USER/DOCKERHUB_TOKEN, ~/.config/digit3/dockerhub.env, or install.sh --hub-user/--hub-token"
fi

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
