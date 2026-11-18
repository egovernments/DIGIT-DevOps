#!/usr/bin/env bash
# Argo CD config-management plugin "digit-helmfile" (Argo CD mode of the one-click install).
# Runs in the argocd-repo-server sidecar (helmfile image), with the current directory =
# deploy-as-code/helm of the team's fork. Prints Kubernetes manifests on stdout only.
#
#   MODE=apps     root Application "digit": one Argo CD Application per installed helmfile
#                 release, ordered by the release label "wave" (argocd.argoproj.io/sync-wave)
#   MODE=release  one release (RELEASE + NAMESPACE + HELMFILE = its layer helmfile):
#                 `helmfile template` of just that release
#
# Inputs (Application spec.source.plugin.env -> ARGOCD_ENV_*): MODE, ENV (environment name),
# RELEASE, NAMESPACE, HELMFILE. Argo CD also sets ARGOCD_APP_SOURCE_REPO_URL / _TARGET_REVISION
# / _PATH, ARGOCD_APP_NAMESPACE. Values are exactly the helmfile mode's: the two environment
# files environments/<ENV>.yaml and <ENV>-secrets.yaml (helm-secrets; sops decrypts with the
# cluster's managed identity).
set -euo pipefail
# Several renders run at once (reposerver.parallelism.limit). `helm repo add` locks
# repositories.yaml for at most 30s, so each render gets its own HELM_CONFIG_HOME; the
# downloaded chart-repo indexes (HELM_CACHE_HOME) stay shared.
export HOME=/tmp HELM_CACHE_HOME=/tmp/helm/cache
HELM_CONFIG_HOME=$(mktemp -d /tmp/helm-config.XXXXXX); export HELM_CONFIG_HOME
trap 'rm -rf "$HELM_CONFIG_HOME"' EXIT
env=${ARGOCD_ENV_ENV:?ENV missing}
[[ $env =~ ^[a-z][a-z0-9-]{1,18}[a-z0-9]$ ]] || { echo "bad ENV '$env'" >&2; exit 1; }
export DIGIT_ENV_FILE="$PWD/environments/$env.yaml" DIGIT_SECRETS_FILE="$PWD/environments/$env-secrets.yaml"
log=$(mktemp)
run() { "$@" 2>"$log" || { cat "$log" >&2; exit 1; }; }

case "${ARGOCD_ENV_MODE:?MODE missing}" in
  apps)
    run helmfile -f digit-helmfile.yaml.gotmpl list --output json > /tmp/releases.json
    jq -r --arg repo "$ARGOCD_APP_SOURCE_REPO_URL" --arg rev "$ARGOCD_APP_SOURCE_TARGET_REVISION" \
          --arg path "$ARGOCD_APP_SOURCE_PATH" --arg argons "${ARGOCD_APP_NAMESPACE:-argocd}" \
          --arg env "$env" '
      .[] | select(.installed)
      | (.labels | split(",") | map(split(":") | {(.[0]): (.[1:] | join(":"))}) | add) as $l
      | {
          apiVersion: "argoproj.io/v1alpha1", kind: "Application",
          metadata: {
            name: .name, namespace: $argons,
            labels: {"digit.org/layer": ($l.layer // "none")},
            annotations: {"argocd.argoproj.io/sync-wave": ($l.wave // "10")},
            finalizers: ["resources-finalizer.argocd.argoproj.io"]
          },
          spec: {
            project: "default",
            source: {repoURL: $repo, targetRevision: $rev, path: $path,
              plugin: {name: "digit-helmfile", env: [
                {name: "MODE", value: "release"}, {name: "ENV", value: $env}, {name: "RELEASE", value: .name},
                {name: "NAMESPACE", value: .namespace},
                {name: "HELMFILE", value: ("helmfiles/" + $l.layer + ".yaml.gotmpl")}]}},
            destination: {server: "https://kubernetes.default.svc", namespace: .namespace},
            syncPolicy: {
              automated: {prune: true, selfHeal: true},
              syncOptions: ["CreateNamespace=true", "ServerSideApply=true", "SkipDryRunOnMissingResource=true"],
              retry: {limit: 20, backoff: {duration: "30s", factor: 2, maxDuration: "10m"}}
            }
          }
        }
      | "---", (. | tojson)' /tmp/releases.json
    ;;
  release)
    : "${ARGOCD_ENV_RELEASE:?RELEASE missing}" "${ARGOCD_ENV_NAMESPACE:?NAMESPACE missing}"
    hf=${ARGOCD_ENV_HELMFILE:-digit-helmfile.yaml.gotmpl}
    case "$hf" in helmfiles/*.yaml.gotmpl|digit-helmfile.yaml.gotmpl) ;; *) echo "bad HELMFILE '$hf'" >&2; exit 1 ;; esac
    out=$(mktemp)
    # --api-versions: CRD groups this install provides, so charts render the same objects
    # (ServiceMonitors, Certificates) as helmfile mode does against the live cluster.
    run helmfile -f "$hf" template --include-crds --skip-tests \
      --args "--api-versions=monitoring.coreos.com/v1 --api-versions=cert-manager.io/v1" \
      -l "name=${ARGOCD_ENV_RELEASE},namespace=${ARGOCD_ENV_NAMESPACE}" > "$out"
    cat "$out"
    ;;
  *) echo "unknown MODE '$ARGOCD_ENV_MODE'" >&2; exit 1 ;;
esac
