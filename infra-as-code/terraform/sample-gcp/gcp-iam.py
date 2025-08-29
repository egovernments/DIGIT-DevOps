import os
import subprocess
import sys
import glob
import json
import yaml

def run_cmd(cmd):
    """Run a shell command and return output"""
    try:
        result = subprocess.check_output(cmd, shell=True, text=True)
        return result.strip()
    except subprocess.CalledProcessError as e:
        print(f"❌ Error running command: {e.output}")
        sys.exit(1)

GCLOUD_CONFIG_DIR = os.path.expanduser("~/.config/gcloud/configurations")

def list_gcloud_profiles():
    """List available gcloud profiles from configuration directory."""
    profiles = []
    if os.path.exists(GCLOUD_CONFIG_DIR):
        for path in glob.glob(os.path.join(GCLOUD_CONFIG_DIR, "config_*")):
            profiles.append(os.path.basename(path).replace("config_", ""))
    return profiles

def get_current_account():
    """Return the currently active gcloud account."""
    try:
        result = subprocess.run(
            ["gcloud", "auth", "list", "--filter=status:ACTIVE", "--format=value(account)"],
            capture_output=True, text=True, check=True
        )
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return None
    
def get_project_id():
    """Fetch project ID from active gcloud profile"""
    project_id = run_cmd("gcloud config get-value project")
    if project_id == "(unset)" or not project_id:
        print("❌ No project is set for the current profile. Please set it using:")
        print("   gcloud config set project PROJECT_ID")
        sys.exit(1)
    return project_id


def create_or_modify_profile(profile_name):
    """Create a new profile, or modify it if it already exists."""
    import subprocess, os, sys

    # Check if profile already exists
    result = subprocess.run(
        ["gcloud", "config", "configurations", "list", "--format=value(name)"],
        capture_output=True, text=True, check=True
    )
    profiles = result.stdout.strip().splitlines()

    if profile_name in profiles:
        print(f"\n⚠️ Profile '{profile_name}' already exists. Modifying it...")
    else:
        print(f"\n✨ Creating new profile '{profile_name}'...")
        subprocess.run(["gcloud", "config", "configurations", "create", profile_name], check=True)

    # Activate profile
    subprocess.run(["gcloud", "config", "configurations", "activate", profile_name], check=True)

    # Authentication flow
    print("\nChoose authentication method:")
    print("1. User login (browser-based OAuth2)")
    print("2. Service account JSON key")

    choice = input("Enter choice [1/2]: ").strip()

    if choice == "1":
        subprocess.run(["gcloud", "auth", "login", "--brief"], check=True)
    elif choice == "2":
        key_file = input("Enter path to service account JSON key: ").strip()
        if not os.path.exists(key_file):
            print(f"❌ Service account key file not found: {key_file}")
            sys.exit(1)
        subprocess.run([
            "gcloud", "auth", "activate-service-account",
            f"--key-file={key_file}"
        ], check=True)
    else:
        print("❌ Invalid choice. Exiting.")
        sys.exit(1)

    # Update the profile with the authenticated account
    account = get_current_account()
    if account:
        subprocess.run(["gcloud", "config", "set", "account", account], check=True)
        print(f"✅ Profile '{profile_name}' now uses account: {account}")
    else:
        print("⚠️ Could not detect current account after authentication.")

    # 🚀 Ask for project, region, zone (new)
    project = input("\nEnter project ID to use for this profile: ").strip()
    if project:
        subprocess.run(["gcloud", "config", "set", "project", project], check=True)

    region = input("Enter default region (or press Enter to skip): ").strip()
    if region:
        subprocess.run(["gcloud", "config", "set", "compute/region", region], check=True)

    zone = input("Enter default zone (or press Enter to skip): ").strip()
    if zone:
        subprocess.run(["gcloud", "config", "set", "compute/zone", zone], check=True)

    print(f"🎯 Profile '{profile_name}' updated with project '{project}', region '{region}', zone '{zone}'")

def run_cmd(cmd):
    """Run a shell command and return output"""
    try:
        result = subprocess.check_output(cmd, shell=True, text=True)
        return result.strip()
    except subprocess.CalledProcessError as e:
        print(f"❌ Error running command: {e.output}")
        sys.exit(1)

def load_required_permissions(file_path="permissions.yaml"):
    """Load required permissions from a YAML file and flatten into a list."""
    if not os.path.exists(file_path):
        print(f"❌ Permissions file not found: {file_path}")
        sys.exit(1)

    with open(file_path, "r") as f:
        data = yaml.safe_load(f)

    required_permissions = []
    for _, perms in data.items():
        required_permissions.extend(perms)

    return required_permissions

def detect_entity_type():
    """Detect if current account is user or service account"""
    account = run_cmd("gcloud config get-value account")
    if account.endswith(".gserviceaccount.com"):
        entity_type = "serviceAccount"
    else:
        entity_type = "user"
    return account, entity_type

def get_project_id():
    """Fetch the active project from gcloud config"""
    return run_cmd("gcloud config get-value project")

def validate_permissions(project_id, required_permissions):
    """Validate each permission using IAM Policy Troubleshooter"""
    account, entity_type = detect_entity_type()
    print(f"🔍 Validating permissions for {account} ({entity_type})...")

    full_resource = f"//cloudresourcemanager.googleapis.com/projects/{project_id}"

    missing = []
    for perm in required_permissions:
        cmd = (
            f"gcloud policy-intelligence troubleshoot-policy iam "
            f"{full_resource} "
            f"--principal-email={account} "
            f"--permission={perm} "
            f"--format=json"
        )
        output = run_cmd(cmd)

        try:
            result = json.loads(output)
            allow_state = result.get("allowPolicyExplanation", {}).get("allowAccessState", "")
        except json.JSONDecodeError:
            print("❌ Failed to parse troubleshoot-policy output.")
            sys.exit(1)

        if allow_state != "ALLOW_ACCESS_STATE_GRANTED":
            missing.append(perm)

    if missing:
        print("❌ Missing permissions:")
        for perm in missing:
            print(f"   - {perm}")
        sys.exit(1)
    else:
        print("✅ All required permissions are granted.")


def main():
    profiles = list_gcloud_profiles()

    if not profiles:
        print("⚠️ No gcloud profiles found. Let's create one.")
        profile_name = input("Enter the new profile name (Press Enter for 'default'): ").strip()
        if not profile_name:
            profile_name = "default"
        create_or_modify_profile(profile_name)
        project_id = get_project_id()
        required_permissions = load_required_permissions("permissions.yaml")
        validate_permissions(project_id, required_permissions)
        return

    print("\nAvailable gcloud profiles:")
    for idx, p in enumerate(profiles, 1):
        print(f"{idx}. {p}")
    print(f"{len(profiles)+1}. Create new profile")

    if "default" in profiles:
        while True:
            choice = input("\nA 'default' profile exists. Do you want to use it? [y/n]: ").strip().lower()
            if choice == "y":
                subprocess.run(["gcloud", "config", "configurations", "activate", "default"], check=True)
                print("✅ Using default profile.")
                profile_name = "default"
                project_id = get_project_id()
                required_permissions = load_required_permissions("permissions.yaml")
                validate_permissions(project_id, required_permissions)
                return
            elif choice == "n":
                break
            else:
                print("❌ Invalid input. Please enter 'y' or 'n'.")

    choice = input(f"\nSelect a profile [1-{len(profiles)+1}]: ").strip()
    try:
        choice = int(choice)
    except ValueError:
        print("❌ Invalid input. Exiting.")
        sys.exit(1)

    if choice == len(profiles)+1:
        profile_name = input("Enter the new profile name (Press Enter for 'default'): ").strip()
        if not profile_name:
            profile_name = "default"
        create_or_modify_profile(profile_name)
    elif 1 <= choice <= len(profiles):
        profile_name = profiles[choice-1]
        subprocess.run(["gcloud", "config", "configurations", "activate", profile_name], check=True)
        print(f"✅ Using profile '{profile_name}'.")
        result = subprocess.run(
        ["gcloud", "config", "list", "--format=json"],
        capture_output=True, text=True, check=True
        )
        config = json.loads(result.stdout)
        account = config.get("core", {}).get("account")
        project = config.get("core", {}).get("project")
        if not account or not project:
            print(f"⚠️ Profile '{profile_name}' looks incomplete (missing account/project).")
            print("👉 Let's configure it now...")
            create_or_modify_profile(profile_name)
    else:
        print("❌ Invalid choice. Exiting.")
        sys.exit(1)
    project_id = get_project_id()
    required_permissions = load_required_permissions("permissions.yaml")
    validate_permissions(project_id, required_permissions)


if __name__ == "__main__":
    main()
