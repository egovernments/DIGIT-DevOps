import os
import json
import subprocess
import sys
import fnmatch

REQUIRED_ACTIONS = [
    "Microsoft.Resources/subscriptions/resourceGroups/*",
    "Microsoft.Network/virtualNetworks/*",
    "Microsoft.ContainerService/managedClusters/*",
    "Microsoft.DBforPostgreSQL/*",
    "Microsoft.Network/natGateways/*",
    "Microsoft.Network/publicIPAddresses/*",
    "Microsoft.Storage/*"
]

def run_command(command, capture_output=True):
    result = subprocess.run(command, capture_output=capture_output, text=True)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, result.args, output=result.stdout, stderr=result.stderr)
    return result.stdout.strip()

def list_existing_profiles():
    try:
        output = run_command(["az", "account", "list", "--output", "json"])
        return json.loads(output)
    except Exception:
        return []

def prompt_existing_profile(profiles):
    print("\n🧾 Available Azure Profiles:")
    for idx, profile in enumerate(profiles):
        print(f"{idx + 1}. {profile['name']} ({profile['user']['name']})")
    print("0. Enter new credentials")

    while True:
        choice = input("👉 Select a profile or enter 0 to configure a new one: ")
        if choice.isdigit():
            choice = int(choice)
            if 0 <= choice <= len(profiles):
                return profiles[choice - 1]['name'] if choice != 0 else None
        print("⚠️ Invalid choice.")

def configure_default_profile():
    print("🛠️ Configuring new profile as 'default'...")
    client_id = input("🔑 Enter Client ID: ").strip()
    client_secret = input("🕵️ Enter Client Secret: ").strip()
    tenant_id = input("🏢 Enter Tenant ID: ").strip()

    try:
        run_command([
            "az", "login", 
            "--service-principal", 
            "--username", client_id,
            "--password", client_secret,
            "--tenant", tenant_id
        ])
        print("✅ Logged in successfully.")
    except subprocess.CalledProcessError:
        print("❌ Failed to authenticate with provided credentials.")
        sys.exit(1)

    # Fetch and return the subscription ID
    try:
        account_info = json.loads(run_command(["az", "account", "show", "-o", "json"]))
        return account_info["id"]
    except Exception:
        print("❌ Failed to retrieve subscription ID after login.")
        sys.exit(1)

def set_active_profile(subscription_id):
    try:
        run_command(["az", "account", "set", "--subscription", subscription_id])
        print(f"✅ Subscription '{subscription_id}' is set as active.")
    except subprocess.CalledProcessError:
        print(f"❌ Failed to set subscription '{subscription_id}' as active.")
        sys.exit(1)

def get_current_sp_object_id():
    account_info = json.loads(run_command(["az", "account", "show", "-o", "json"]))
    client_id = account_info.get("user", {}).get("name")
    if not client_id:
        raise RuntimeError("Unable to extract client_id from current profile.")

    object_id = run_command([
        "az", "ad", "sp", "list",
        "--filter", f"appId eq '{client_id}'",
        "--query", "[0].id",
        "-o", "tsv"
    ])
    
    if not object_id:
        raise RuntimeError("Failed to get Service Principal objectId. Ensure the SP exists and has permissions.")
    
    return object_id

def get_sp_permissions(object_id):
    role_assignments = json.loads(run_command([
        "az", "role", "assignment", "list",
        "--assignee", object_id,
        "--query", "[].roleDefinitionName",
        "-o", "json"
    ]))

    all_permissions = set()
    for role in role_assignments:
        role_defs = json.loads(run_command([
            "az", "role", "definition", "list",
            "--name", role,
            "-o", "json"
        ]))
        for rd in role_defs:
            for perm in rd.get("permissions", []):
                all_permissions.update(perm.get("actions", []))
    return all_permissions

def matches_permission(required, granted):
    return fnmatch.fnmatchcase(required, granted)

def check_permissions(object_id):
    print("🔎 Checking required permissions...")
    permissions = get_sp_permissions(object_id)
    for required in REQUIRED_ACTIONS:
        if not any(matches_permission(required, allowed) for allowed in permissions):
            print(f"❌ Missing permission: {required}")
            sys.exit(1)
        else:
            print(f"✅ Permission granted: {required}")

def main():
    print("🚀 Azure Credential & Permission Validator")

    profiles = list_existing_profiles()
    profile_names = [p['name'] for p in profiles]

    if "default" in profile_names:
        print("✅ 'default' profile is already configured. Using it.")
        set_active_profile("default")
    elif profiles:
        selected = prompt_existing_profile(profiles)
        if selected:
            set_active_profile(selected)
        else:
            subscription_id = configure_default_profile()
            set_active_profile(subscription_id)
    else:
        subscription_id = configure_default_profile()
        set_active_profile(subscription_id)

    object_id = get_current_sp_object_id()
    check_permissions(object_id)

if __name__ == "__main__":
    main()
