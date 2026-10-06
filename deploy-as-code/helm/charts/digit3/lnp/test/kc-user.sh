#!/bin/bash
# kc-user.sh <scripts-dir> <realm> <search>  — Keycloak users matching <search> (username, e-mail, required actions). No secrets printed.
SCRIPTS=$1; REALM=$2; Q=$3; source "$SCRIPTS/lib.sh"; load_env; set +e; trap - ERR
KCIP=$(kubectl get svc keycloak -n keycloak -o jsonpath='{.spec.clusterIP}'); KCUSER=$(sops_get 'cluster-configs.secrets.kc-admin.username')
printf '%s\n%s\n' "$KCUSER" "$(sops_get 'cluster-configs.secrets.kc-admin.password')" | vm_ssh "read -r KCUSER; read -r KCPW
KC='http://keycloak.keycloak.svc.cluster.local:8080/keycloak'; RES='--resolve keycloak.keycloak.svc.cluster.local:8080:$KCIP'
ADM=\$(curl -s \$RES -X POST \$KC/realms/master/protocol/openid-connect/token --data-urlencode grant_type=password --data-urlencode client_id=admin-cli --data-urlencode \"username=\$KCUSER\" --data-urlencode \"password=\$KCPW\" | python3 -c 'import sys,json;print(json.load(sys.stdin).get(\"access_token\",\"\"))')
curl -s \$RES -H \"Authorization: Bearer \$ADM\" \"\$KC/admin/realms/$REALM/users?search=$(printf %s "$Q" | sed 's/+/%2B/g')&max=20\" | python3 -c 'import sys,json
for u in json.load(sys.stdin): print(\"  %-28s %-40s enabled=%s required=%s\" % (u.get(\"username\"), u.get(\"email\"), u.get(\"enabled\"), u.get(\"requiredActions\")))'"
