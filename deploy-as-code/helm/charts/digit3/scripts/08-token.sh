#!/usr/bin/env bash
# 08 — mint a Kong-ready bearer token for a tenant user (INSTALL.md "Calling
# the APIs through Kong"). The gateway's keycloak-rbac plugin authorizes each
# request with a UMA check against Keycloak's in-cluster URL, so a working
# token must satisfy three things this script takes care of:
#   1. issued by the SAME issuer the plugin uses (cluster-DNS, not ClusterIP
#      or the public URL — otherwise 401 "Token rejected by Keycloak")
#   2. issued via the `auth-server` confidential client (admin-cli tokens
#      carry no roles — otherwise 403 "No roles found in token")
#   3. for a user with realm roles (tenant admins get SUPERUSER/ADMIN)
#
# Usage: ./08-token.sh <TENANT-CODE> <email> [password]
#   password omitted -> prompted silently. Prints the token and a sample curl.
source "$(dirname "$0")/lib.sh"
load_env
ensure_tunnel

[ $# -ge 2 ] || die "usage: $0 <TENANT-CODE> <email> [password]"
REALM="$1" USERNAME="$2" PASSWORD="${3:-}"
if [ -z "$PASSWORD" ]; then
  [ -t 0 ] || die "no password given and no terminal to prompt on — pass it as the 3rd argument"
  read -r -s -p "password for $USERNAME: " PASSWORD; echo
fi

KCIP=$(kubectl get svc keycloak -n keycloak -o jsonpath='{.spec.clusterIP}')
KGIP=$(kubectl get svc kong-kong-proxy -n egov -o jsonpath='{.spec.clusterIP}')
[ -n "$KCIP" ] || die "keycloak service not found"

# All secret material travels via stdin/remote shell vars — never argv, never displayed.
# The admin username is read HERE with sops_get: an earlier inline
# `$(sops -d --extract '[\"…\"]' … || echo digit)` inside this double-quoted
# string kept its backslashes, so sops failed and the fallback logged in as
# "digit" — which only worked on environments whose admin happens to be "digit".
KCUSER=$(sops_get 'cluster-configs.secrets.kc-admin.username')
[ -n "$KCUSER" ] || die "kc-admin.username missing in $SECRETS_FILE"
TOKEN=$( printf '%s\n%s\n%s\n' "$KCUSER" "$(sops_get 'cluster-configs.secrets.kc-admin.password')" "$PASSWORD" | \
  vm_ssh "read -r KCUSER; read -r KCPW; read -r USERPW
KC='http://keycloak.keycloak.svc.cluster.local:8080/keycloak'
RES='--resolve keycloak.keycloak.svc.cluster.local:8080:$KCIP'
ADM=\$(curl -s \$RES -X POST \$KC/realms/master/protocol/openid-connect/token \
  --data-urlencode grant_type=password --data-urlencode client_id=admin-cli \
  --data-urlencode \"username=\$KCUSER\" --data-urlencode \"password=\$KCPW\" | \
  python3 -c 'import sys,json;print(json.load(sys.stdin).get(\"access_token\",\"\"))')
[ -n \"\$ADM\" ] || { echo NOADMIN; exit 0; }
CID=\$(curl -s \$RES -H \"Authorization: Bearer \$ADM\" \"\$KC/admin/realms/$REALM/clients?clientId=auth-server\" | \
  python3 -c 'import sys,json;d=json.load(sys.stdin);print(d[0][\"id\"] if d else \"\")')
[ -n \"\$CID\" ] || { echo NOCLIENT; exit 0; }
CSEC=\$(curl -s \$RES -H \"Authorization: Bearer \$ADM\" \$KC/admin/realms/$REALM/clients/\$CID/client-secret | \
  python3 -c 'import sys,json;print(json.load(sys.stdin).get(\"value\",\"\"))')
curl -s \$RES -X POST \$KC/realms/$REALM/protocol/openid-connect/token \
  --data-urlencode grant_type=password --data-urlencode client_id=auth-server \
  --data-urlencode \"client_secret=\$CSEC\" --data-urlencode \"username=$USERNAME\" --data-urlencode \"password=\$USERPW\" | \
  python3 -c 'import sys,json;r=json.load(sys.stdin);print(r.get(\"access_token\") or \"NOTOKEN:\"+r.get(\"error_description\",r.get(\"error\",\"\")))'" )

case "$TOKEN" in
  NOADMIN)   die "keycloak admin login failed (kc-admin secret vs cluster mismatch?)" ;;
  NOCLIENT)  die "realm $REALM has no auth-server client — does the tenant exist?" ;;
  NOTOKEN:*) die "user token refused: ${TOKEN#NOTOKEN:}" ;;
  "")        die "no token returned" ;;
esac

note "token minted for $USERNAME in realm $REALM (expires per realm settings)"
echo
echo "$TOKEN"
echo
echo "sample call (run on the VM — see INSTALL.md on port-forward reliability):"
echo "  curl -H 'Authorization: Bearer <token>' -H 'X-Tenant-ID: $REALM' \\"
echo "       -H 'Host: $DOMAIN' http://$KGIP:8000/individual/v3/individuals"
