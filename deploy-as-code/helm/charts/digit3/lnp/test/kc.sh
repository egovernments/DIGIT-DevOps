#!/bin/bash
# kc.sh <scripts-dir> <realm> <METHOD> <admin-api-path> [json-body]  — Keycloak admin API call from the VM, JSON to stdout.
# Admin creds come from sops via lib.sh and travel over the ssh stdin; nothing secret is printed.
SCRIPTS=$1; REALM=$2; M=$3; P=$4; BODY=${5:-}
source "$SCRIPTS/lib.sh"; load_env; set +e; trap - ERR; set +u
KCIP=$(kubectl get svc keycloak -n keycloak -o jsonpath='{.spec.clusterIP}'); KCUSER=$(sops_get 'cluster-configs.secrets.kc-admin.username')
printf '%s\n%s\n%s' "$KCUSER" "$(sops_get 'cluster-configs.secrets.kc-admin.password')" "$BODY" | vm_ssh "read -r KCUSER; read -r KCPW; BODY=\$(cat)
KC=http://keycloak.keycloak.svc.cluster.local:8080/keycloak; RES='--resolve keycloak.keycloak.svc.cluster.local:8080:$KCIP'
ADM=\$(curl -s \$RES -X POST \$KC/realms/master/protocol/openid-connect/token --data-urlencode grant_type=password --data-urlencode client_id=admin-cli --data-urlencode \"username=\$KCUSER\" --data-urlencode \"password=\$KCPW\" | python3 -c 'import sys,json;print(json.load(sys.stdin).get(\"access_token\",\"\"))')
[ -n \"\$ADM\" ] || { echo '{\"error\":\"NOADMIN\"}'; exit 0; }
if [ -n \"\$BODY\" ]; then printf '%s' \"\$BODY\" | curl -s \$RES -X $M \"\$KC/admin/realms/$REALM$P\" -H \"Authorization: Bearer \$ADM\" -H 'Content-Type: application/json' -d @- -w '\n%{http_code}'
else curl -s \$RES -X $M \"\$KC/admin/realms/$REALM$P\" -H \"Authorization: Bearer \$ADM\" -w '\n%{http_code}'; fi"
