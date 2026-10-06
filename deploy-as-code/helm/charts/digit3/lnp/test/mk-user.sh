#!/bin/bash
# mk-user.sh <scripts-dir> <realm> <email> <password-env-var> <env-file> <role>...  — Keycloak user with realm roles (test users).
# Existing users (409) get the password reset (non-temporary) and their required actions cleared — e.g. the UPDATE_PASSWORD that
# _provision-employees leaves on freshly created employees.
SCRIPTS=$1; REALM=$2; EMAIL=$3; PWVAR=$4; ENVFILE=$5; shift 5; ROLES="$*"
source "$SCRIPTS/lib.sh"; load_env; set +e; trap - ERR; set +u; source "$ENVFILE"
KCIP=$(kubectl get svc keycloak -n keycloak -o jsonpath='{.spec.clusterIP}'); KCUSER=$(sops_get 'cluster-configs.secrets.kc-admin.username')
printf '%s\n%s\n%s\n' "$KCUSER" "$(sops_get 'cluster-configs.secrets.kc-admin.password')" "${!PWVAR}" | vm_ssh "read -r KCUSER; read -r KCPW; read -r UPW
KC='http://keycloak.keycloak.svc.cluster.local:8080/keycloak'; RES='--resolve keycloak.keycloak.svc.cluster.local:8080:$KCIP'
ADM=\$(curl -s \$RES -X POST \$KC/realms/master/protocol/openid-connect/token --data-urlencode grant_type=password --data-urlencode client_id=admin-cli --data-urlencode \"username=\$KCUSER\" --data-urlencode \"password=\$KCPW\" | python3 -c 'import sys,json;print(json.load(sys.stdin).get(\"access_token\",\"\"))')
[ -n \"\$ADM\" ] || { echo NOADMIN; exit 0; }
H=\"Authorization: Bearer \$ADM\"
curl -s \$RES -o /dev/null -w 'create user -> %{http_code}\n' -X POST \$KC/admin/realms/$REALM/users -H \"\$H\" -H 'Content-Type: application/json' -d '{\"username\":\"$EMAIL\",\"email\":\"$EMAIL\",\"emailVerified\":true,\"enabled\":true,\"firstName\":\"Citizen\",\"lastName\":\"Test\"}'
UID_=\$(curl -s \$RES -H \"\$H\" \"\$KC/admin/realms/$REALM/users?username=$(printf %s "$EMAIL" | sed 's/+/%2B/g')&exact=true\" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0][\"id\"] if d else \"\")')
curl -s \$RES -o /dev/null -w 'set password -> %{http_code}\n' -X PUT \$KC/admin/realms/$REALM/users/\$UID_/reset-password -H \"\$H\" -H 'Content-Type: application/json' -d \"{\\\"type\\\":\\\"password\\\",\\\"value\\\":\\\"\$UPW\\\",\\\"temporary\\\":false}\"
curl -s \$RES -o /dev/null -w 'clear required actions -> %{http_code}\n' -X PUT \$KC/admin/realms/$REALM/users/\$UID_ -H \"\$H\" -H 'Content-Type: application/json' -d '{\"requiredActions\":[]}'
for r in $ROLES; do RJ=\$(curl -s \$RES -H \"\$H\" \$KC/admin/realms/$REALM/roles/\$r); curl -s \$RES -o /dev/null -w \"role \$r -> %{http_code}\n\" -X POST \$KC/admin/realms/$REALM/users/\$UID_/role-mappings/realm -H \"\$H\" -H 'Content-Type: application/json' -d \"[\$RJ]\"; done"
