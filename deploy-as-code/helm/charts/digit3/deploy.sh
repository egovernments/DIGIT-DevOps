#!/usr/bin/env bash
# Deploy wrapper for the digit3 single-node install.
#
# The env secrets live age-encrypted in environments/azure-k3s-secrets.yaml
# (key: ~/.config/sops/age/keys.txt). Both helmfiles reference the decrypted
# copy (azure-k3s-secrets.dec.yaml, git-ignored), which this script creates
# for the duration of the helmfile run and removes afterwards.
#
# Usage (from anywhere):
#   ./deploy.sh -f backboneservices-helmfile.yaml apply     # backbone first
#   ./deploy.sh -f digit3services-helmfile.yaml apply       # then services
#   ./deploy.sh -f digit3services-helmfile.yaml -l name=keycloak diff
#
# Set KUBECONFIG to the target cluster before running, e.g.:
#   export KUBECONFIG=~/Documents/modulith-deployment/modulith-kubeconfig.yaml
set -euo pipefail
cd "$(dirname "$0")"

SRC=../../environments/azure-k3s-secrets.yaml
DEC=../../environments/azure-k3s-secrets.dec.yaml

trap 'rm -f "$DEC"' EXIT
sops -d "$SRC" > "$DEC"

helmfile "$@"
