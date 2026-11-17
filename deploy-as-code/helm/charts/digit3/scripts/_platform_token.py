#!/usr/bin/env python3
"""Mint a platform-realm token that account's tenant-lifecycle check accepts.

Run ON THE VM by 07-seed.sh:  <user>\\n<password>\\n on stdin, Keycloak base URL as argv[1]
(e.g. http://<clusterIP>:8080/keycloak). Prints ONLY the access token.

account (PLATFORM_AUTH_ENABLED=true) requires a master-realm JWT whose realm_access.roles holds
SUPERADMIN. A fresh Keycloak has neither the role (e2e finding E-002) nor a client whose tokens
carry realm_access: admin-cli tokens have no roles scope (E-003). So, idempotently:
  1. create the SUPERADMIN realm role in master and grant it to the bootstrap admin;
  2. create a public `digit-platform` client with direct grants and the `roles` default scope;
  3. password-grant on that client and print the token.
Only the standard library is used; credentials never reach argv or stdout.
"""
import json
import sys
import urllib.error
import urllib.parse
import urllib.request

ROLE = "SUPERADMIN"
CLIENT = "digit-platform"


def call(method, url, token=None, body=None, form=None):
    headers = {}
    data = None
    if token:
        headers["Authorization"] = "Bearer " + token
    if body is not None:
        headers["Content-Type"] = "application/json"
        data = json.dumps(body).encode()
    if form is not None:
        headers["Content-Type"] = "application/x-www-form-urlencoded"
        data = urllib.parse.urlencode(form).encode()
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        return e.code, None


def password_grant(base, client_id, user, password):
    status, resp = call("POST", f"{base}/realms/master/protocol/openid-connect/token",
                        form={"grant_type": "password", "client_id": client_id,
                              "username": user, "password": password, "scope": "openid"})
    if status != 200:
        sys.exit(f"password grant on master/{client_id} failed: HTTP {status}")
    return resp["access_token"]


def main():
    base = sys.argv[1].rstrip("/")
    user = sys.stdin.readline().strip()
    password = sys.stdin.readline().strip()
    if not user or not password:
        sys.exit("keycloak admin credentials missing on stdin")
    admin = f"{base}/admin/realms/master"
    tok = password_grant(base, "admin-cli", user, password)

    # 1. SUPERADMIN role, granted to the bootstrap admin
    status, role = call("GET", f"{admin}/roles/{ROLE}", tok)
    if status == 404:
        call("POST", f"{admin}/roles", tok, {"name": ROLE, "description": "DIGIT platform operator (tenant lifecycle)"})
        status, role = call("GET", f"{admin}/roles/{ROLE}", tok)
    if status != 200:
        sys.exit(f"could not read or create master role {ROLE}: HTTP {status}")
    _, users = call("GET", f"{admin}/users?exact=true&username={urllib.parse.quote(user)}", tok)
    if not users:
        sys.exit("bootstrap admin user not found in master")
    uid = users[0]["id"]
    _, granted = call("GET", f"{admin}/users/{uid}/role-mappings/realm", tok)
    if not any(r.get("name") == ROLE for r in granted or []):
        status, _ = call("POST", f"{admin}/users/{uid}/role-mappings/realm", tok, [role])
        if status not in (200, 204):
            sys.exit(f"could not grant {ROLE} to the bootstrap admin: HTTP {status}")

    # 2. public client whose tokens carry realm_access (the `roles` scope) with SUPERADMIN only.
    # Full scope is off: the master admin's composite role would otherwise put every tenant
    # realm's management roles into the token, which outgrows Tomcat's 8 KB header limit.
    _, clients = call("GET", f"{admin}/clients?clientId={CLIENT}", tok)
    if not clients:
        status, _ = call("POST", f"{admin}/clients", tok, {
            "clientId": CLIENT, "publicClient": True, "directAccessGrantsEnabled": True,
            "standardFlowEnabled": False, "fullScopeAllowed": False,
            "description": "DIGIT platform-operator token client (07-seed.sh)"})
        if status not in (200, 201):
            sys.exit(f"could not create master client {CLIENT}: HTTP {status}")
        _, clients = call("GET", f"{admin}/clients?clientId={CLIENT}", tok)
    client = clients[0]
    cid = client["id"]
    if client.get("fullScopeAllowed", True):
        call("PUT", f"{admin}/clients/{cid}", tok, dict(client, fullScopeAllowed=False))
    _, mapped = call("GET", f"{admin}/clients/{cid}/scope-mappings/realm", tok)
    if not any(r.get("name") == ROLE for r in mapped or []):
        status, _ = call("POST", f"{admin}/clients/{cid}/scope-mappings/realm", tok, [role])
        if status not in (200, 204):
            sys.exit(f"could not map {ROLE} into the {CLIENT} client scope: HTTP {status}")
    _, scopes = call("GET", f"{admin}/client-scopes", tok)
    roles_scope = next((s["id"] for s in scopes or [] if s.get("name") == "roles"), None)
    if roles_scope:
        call("PUT", f"{admin}/clients/{cid}/default-client-scopes/{roles_scope}", tok)

    # 3. the platform token itself (a fresh grant, so the role just granted is in it)
    print(password_grant(base, CLIENT, user, password))


if __name__ == "__main__":
    main()
