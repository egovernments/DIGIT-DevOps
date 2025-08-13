import os
import json
import subprocess
import sys
from pathlib import Path
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

AZURE_CONFIG_PATH = os.path.expanduser("~/.azure")
AZURE_CONFIG_DIR = Path.home() / ".azure"
SERVICE_PRINCIPAL_FILE = AZURE_CONFIG_DIR / "service_principal_entries.json"

def run_command(command, capture_output=True):
    result = subprocess.run(command, capture_output=capture_output, text=True)
    if result.returncode != 0:
        raise subprocess.CalledProcessError(result.returncode, result.args, output=result.stdout, stderr=result.stderr)
    return result.stdout.strip()

def validate_azure_location(location):
    try:
        result = subprocess.run(
            ["az", "account", "list-locations", "--query", "[].name", "-o", "tsv"],
            capture_output=True,
            text=True,
            check=True
        )
        valid_locations = result.stdout.strip().split("\n")

        if location not in valid_locations:
            print(f"❌ ERROR: '{location}' is not a valid Azure location.")
            print("✅ Valid locations are:", ", ".join(valid_locations))
            sys.exit(1)  # Exit with error
        else:
            print(f"✅ '{location}' is a valid Azure location.")

    except subprocess.CalledProcessError as e:
        print("❌ Failed to fetch Azure locations. Ensure Azure CLI is installed and logged in.")
        sys.exit(1)

def run_az_cli(cmd):
    try:
        output = subprocess.check_output(cmd, shell=True)
        return json.loads(output)
    except subprocess.CalledProcessError as e:
        print(f"❌ Error running az command: {e.output.decode()}")
        return []

def validate_profile(profile):
    if profile["type"] == "sp":
        try:
            output = run_command([
                "az", "login",
                "--service-principal",
                "--username", profile["client_id"],
                "--password", profile["client_secret"],
                "--tenant", profile["tenant"],
                "--output", "json"
            ])
            login_data = json.loads(output)
            profile["subscription"] = login_data[0]["id"] if login_data else None
            print(f"✅ SP credentials validated successfully for {profile['client_id']}")
            return True
        except Exception as e:
            print(f"❌ Failed to authenticate SP: {str(e)}")
            return False
    else:
        try:
            result = run_command(["az", "account", "show", "--output", "json"])
            data = json.loads(result)
            if data.get("id") == profile["subscription"]:
                print("✅ User credentials are active.")
                return True
            else:
                print("⚠️ User profile subscription mismatch.")
                return False
        except Exception as e:
            print(f"❌ Failed to authenticate user profile: {str(e)}")
            return False

def get_user_profiles(subscription_id=None):
    accounts = run_az_cli("az account list --output json")
    user_profiles = []

    for acc in accounts:
        if acc.get("user") and acc.get("user").get("type") == "user":
            # Only filter if subscription_id is explicitly passed
            if subscription_id is None or acc.get("id") == subscription_id:
                user_profiles.append({
                    "name": acc.get("name"),
                    "subscription": acc.get("id"),
                    "type": "user",
                    "user": acc.get("user").get("name")
                })

    return user_profiles

def get_sp_profiles(subscription_id=None):
    if not SERVICE_PRINCIPAL_FILE.exists():
        return []

    try:
        with open(SERVICE_PRINCIPAL_FILE) as f:
            profiles = json.load(f)
    except json.JSONDecodeError:
        print("❌ Error parsing service_principal_entries.json")
        return []

    filtered = []
    for p in profiles:
        tenant = p.get("tenant")
        client_id = p.get("client_id")
        client_secret = p.get("client_secret")

        if not (tenant and client_id and client_secret):
            continue

        try:
            # Try logging in with the SP to get its subscription
            login_result = run_command([
                "az", "login",
                "--service-principal",
                "--username", client_id,
                "--password", client_secret,
                "--tenant", tenant,
                "--output", "json"
            ])
            login_data = json.loads(login_result)
            sp_subscription = login_data[0]["id"] if login_data else None

            # Only keep if no filtering or if subscription matches
            if subscription_id is None or sp_subscription == subscription_id:
                filtered.append({
                    "tenant": tenant,
                    "client_id": client_id,
                    "client_secret": client_secret,
                    "subscription": sp_subscription,
                    "type": "sp"
                })

        except Exception as e:
            print(f"⚠️ Failed to validate SP with Client ID {client_id}: {str(e)}")

    return filtered

def prompt_for_new_profile():
    print("⚙️  Configure a new Azure Service Principal profile")
    tenant = input("Enter Tenant ID: ").strip()
    client_id = input("Enter Client ID: ").strip()
    client_secret = input("Enter Client Secret: ").strip()

    # ✅ Fetch subscription ID right away
    try:
        login_result = run_command([
            "az", "login",
            "--service-principal",
            "--username", client_id,
            "--password", client_secret,
            "--tenant", tenant,
            "--output", "json"
        ])
        login_data = json.loads(login_result)
        subscription_id = login_data[0]["id"] if login_data else None
    except Exception as e:
        print(f"❌ Failed to fetch subscription ID for new SP: {str(e)}")
        subscription_id = None

    return {
        "tenant": tenant,
        "client_id": client_id,
        "client_secret": client_secret,
        "subscription": subscription_id,
        "type": "sp"
    }

def select_or_create_profile():
    # Try to get current subscription
    # current_sub = run_az_cli("az account show --output json")
    # subscription_id = current_sub.get("id") if current_sub else None

    user_profiles = get_user_profiles(None)
    sp_profiles = get_sp_profiles(None)

    all_profiles = user_profiles + sp_profiles

    if all_profiles:
        print("🔍 Found the following Azure profiles under the current subscription:")
        for i, profile in enumerate(all_profiles, 1):
            if profile["type"] == "user":
                print(f"{i}. User Profile: {profile['user']} | Sub: {profile['subscription']}")
            else:
                print(f"{i}. SP Profile: ClientID {profile['client_id']} | Sub: {profile['subscription']}")
        choice = input("Select a profile (number), or type 'n' to create a new SP profile: ").strip()

        if choice.lower() == 'n':
            new_profile = prompt_for_new_profile()
            # 🔍 Check for duplicate SP entry
            for sp in sp_profiles:
                if (
                    sp["type"] == "sp"
                    and sp["client_id"] == new_profile["client_id"]
                    and sp["tenant"] == new_profile["tenant"]
                ):
                    print("⚠️ This Service Principal already exists in your profiles. Skipping addition.")
                    if validate_profile(sp):
                        return sp
                    else:
                        print("❌ Existing profile validation failed. Exiting.")
                        exit(1)
            if not validate_profile(new_profile):
                print("❌ Validation failed. Exiting.")
                exit(1)
            save_sp_profile(new_profile)
            return new_profile
        elif choice.isdigit() and 1 <= int(choice) <= len(all_profiles):
            selected_profile = all_profiles[int(choice) - 1]
            if not validate_profile(selected_profile):
                print("❌ Validation failed. Exiting.")
                exit(1)
            return selected_profile
        else:
            print("❌ Invalid choice. Exiting.")
            exit(1)
    else:
        print("📭 No profiles found under the current subscription.")
        new_profile = prompt_for_new_profile()
        if not validate_profile(new_profile):
            print("❌ Validation failed. Exiting.")
            exit(1)
        save_sp_profile(new_profile)
        return new_profile

def save_sp_profile(profile):
    # Load existing profiles
    if SERVICE_PRINCIPAL_FILE.exists():
        try:
            with open(SERVICE_PRINCIPAL_FILE) as f:
                profiles = json.load(f)
        except json.JSONDecodeError:
            print("⚠️ Malformed service_principal_entries.json. Starting fresh.")
            profiles = []
    else:
        profiles = []

    updated = False
    for i, existing in enumerate(profiles):
        if (
            existing.get("client_id") == profile["client_id"] and
            existing.get("tenant") == profile["tenant"]
        ):
            # Update the existing profile (overwrite secrets, subscription, type)
            profiles[i] = profile
            updated = True
            print("🔁 Existing profile updated in service_principal_entries.json.")
            break

    if not updated:
        profiles.append(profile)
        print("✅ New profile added to service_principal_entries.json.")

    with open(SERVICE_PRINCIPAL_FILE, "w") as f:
        json.dump(profiles, f, indent=2)

def set_azure_env(profile):
    os.environ["AZURE_CONFIG_DIR"] = AZURE_CONFIG_PATH
    if profile["type"] == "sp":
        os.environ["AZURE_TENANT_ID"] = profile["tenant"]
        os.environ["AZURE_CLIENT_ID"] = profile["client_id"]
        os.environ["AZURE_CLIENT_SECRET"] = profile["client_secret"]
        os.environ["ARM_SUBSCRIPTION_ID"] = profile["subscription"]
        print("✅ Azure environment variables set for selected SP profile.")
    else:
        print("✅ Using user-based Azure profile via Azure CLI. No environment variables required.")

def get_current_sp_object_id(profile):
    """
    Gets the object ID of the selected SP profile (using client_id).
    """
    client_id = profile.get("client_id")
    if not client_id:
        raise RuntimeError("Client ID not found in selected profile.")

    try:
        object_id = run_command([
            "az", "ad", "sp", "list",
            "--filter", f"appId eq '{client_id}'",
            "--query", "[0].id",
            "-o", "tsv"
        ])
    except Exception as e:
        raise RuntimeError(f"Failed to fetch object ID for client_id {client_id}: {e}")

    if not object_id:
        raise RuntimeError("Service Principal not found. Ensure it's created and has proper directory read permissions.")

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
    missing = []
    for required in REQUIRED_ACTIONS:
        if not any(matches_permission(required, allowed) for allowed in permissions):
            print(f"❌ Missing permission: {required}")
            missing.append(required)
    if missing:
        print("\n🚫 Profile is missing required permissions. Please assign proper roles.")
        sys.exit(1)
    else:
        print("\n🎉 All required permissions are granted!")

def main():
    print("🚀 Azure Credential & Permission Validator")

    selected_profile = select_or_create_profile()
    set_azure_env(selected_profile)

    object_id = get_current_sp_object_id(selected_profile)
    check_permissions(object_id)

if __name__ == "__main__":
    main()    
