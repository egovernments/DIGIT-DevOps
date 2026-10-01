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
#   DIGIT_TAG=<tag> ./deploy.sh -f single-container-helmfile.yaml apply   # then a shape
#   DIGIT_TAG=<tag> ./deploy.sh -f single-container-helmfile.yaml -l name=keycloak diff
#
# Set KUBECONFIG to the target cluster before running, e.g.:
#   export KUBECONFIG=~/Documents/modulith-deployment/modulith-kubeconfig.yaml
set -euo pipefail
cd "$(dirname "$0")"

# Per-environment secrets: when scripts/.env names a DOMAIN and a matching
# per-env file exists (environments/azure-k3s-secrets.<domain>.yaml), use it;
# otherwise fall back to the shared legacy file. Helmfiles always reference
# the fixed decrypted name, so selection lives only here.
SRC=../../environments/azure-k3s-secrets.yaml
if [ -f scripts/.env ]; then
  DOMAIN=$(sed -n 's/^DOMAIN="\(.*\)"$/\1/p' scripts/.env)
  export DOMAIN   # *.yaml.gotmpl env files (the LnP overlay) read it with requiredEnv
  if [ -n "$DOMAIN" ] && [ -f "../../environments/azure-k3s-secrets.$DOMAIN.yaml" ]; then
    SRC="../../environments/azure-k3s-secrets.$DOMAIN.yaml"
    echo "secrets: $SRC" >&2
  fi
fi
DEC=../../environments/azure-k3s-secrets.dec.yaml

trap 'rm -f "$DEC"' EXIT
sops -d "$SRC" > "$DEC"

# The VM's real domain, as recorded by 01-cluster.sh, overrides global.domain for every
# release in the run. Without this, backbone releases (minio) take the domain from the base
# environments/azure-k3s.yaml, which can only name one environment — so the MinIO console
# ingress and its certificate were pinned to that one domain on every other cluster. Shape
# overlays set the same value; this just means a release deployed from the shape-agnostic
# backbone helmfile gets it too.
DOMAIN_SET=()
if [ -n "${DOMAIN:-}" ]; then
  DOMAIN_SET=(--set "global.domain=$DOMAIN")
fi

helmfile "${DOMAIN_SET[@]}" "$@"
