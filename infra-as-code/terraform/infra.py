#!/usr/bin/python3
import platform
import subprocess
import sys
import os
import re
from pathlib import Path
import argparse
import tempfile
import importlib.util
import shutil
import json

def cleanup_terraform_artifacts(directory):
    """
    Delete Terraform-generated files and directories in the given directory
    """
    patterns = [".terraform", ".terraform.lock.hcl", "terraform.tfstate", "terraform.tfstate.backup"]
    for pattern in patterns:
        path = directory / pattern
        if path.is_dir():
            shutil.rmtree(path, ignore_errors=True)
            print(f"🧹 Removed directory: {path}")
        elif path.is_file():
            path.unlink()
            print(f"🧹 Removed file: {path}")

def run_terraform_commands(cluster_name, region, cloud_provider, working_dir):
    """
    Run terraform commands in two directories:
    - In remote_state_dir: use a var-file
    - In other_dir: run basic terraform commands
    """
    source_files = ["terraform.tfvars", "main.tf"]
    cluster_clean = re.sub(r'[^A-Za-z0-9]', '', cluster_name)
    replacements = {
        "<cluster_name>": cluster_name,
        "<db_name>": f"{cluster_clean}db",
        "<db_username>": f"{cluster_clean}admin",
        "<region>": region
    }
    backups = []
    def extract_resource_group_name(tf_file):
        with open(tf_file, "r") as f:
            content = f.read()
        match = re.search(r'resource_group\s*=\s*"([^"]+)"', content)
        return match.group(1) if match else None
    
    def get_storage_account_name(resource_group, prefix="tfstate"):
        """Fetch the Azure storage account name by prefix in the given resource group."""
        try:
            result = subprocess.run(
                ["az", "storage", "account", "list", "--resource-group", resource_group, "--query", "[].name", "-o", "json"],
                capture_output=True, text=True, check=True
            )
            accounts = json.loads(result.stdout)
            for acc in accounts:
                if acc.startswith(prefix):
                    return acc
            print(f"⚠️ No storage account found starting with '{prefix}' in resource group '{resource_group}'.")
            return None
        except subprocess.CalledProcessError as e:
            print(f"⚠️ Failed to fetch storage account name: {e}")
            return None
    try:
        for file_name in source_files:
            file_path = Path(working_dir) / file_name
            if file_path.exists():
                path = Path(file_path)
                backup_path = path.with_suffix(".bak")
                # Backup
                shutil.copy(path, backup_path)
                backups.append((file_path, backup_path))
                replace_placeholders(path, replacements)
            else:
                print(f"⚠️ Skipping missing file: {file_name}")
        remote_state_dir = Path(working_dir) / "remote-state"
        # Commands for remote state dir (with var-file)
        remote_state_commands = [
            ["terraform", "init"],
            ["terraform", "plan", "-var-file=../terraform.tfvars"],
            ["terraform", "apply", "-auto-approve", "-var-file=../terraform.tfvars"]
        ]

        # Commands for the other dir (basic commands)
        infra_commands = [
            ["terraform", "init"],
            ["terraform", "plan"],
            ["terraform", "apply", "-auto-approve"]
        ]

        def execute(directory, commands):
            print(f"\n📁 Entering: {directory}")
            for cmd in commands:
                print(f"🔧 Running: {' '.join(cmd)}")
                try:
                    result = subprocess.run(
                        cmd,
                        cwd=directory,
                        check=True
                    )
                    print(f"✅ Output:\n{result.stdout}")
                except subprocess.CalledProcessError as e:
                    print(f"❌ Error running {' '.join(cmd)}:\n{e.stderr}")
                    break  # Stop further execution if one command fails
        cleanup_terraform_artifacts(Path(working_dir))
        cleanup_terraform_artifacts(remote_state_dir)
        execute(remote_state_dir, remote_state_commands)
        if cloud_provider.lower() == "aws":
            execute(Path(working_dir), infra_commands)
        elif cloud_provider.lower() == "azure":
            tf_file = Path(working_dir)/"terraform.tfvars"
            resourcegroup = extract_resource_group_name(tf_file)
            storage_account = get_storage_account_name(resourcegroup)
            storage_account_replacement = {
                "<storage_account>": storage_account
            }
            storage_account_replace_file = Path(working_dir)/"main.tf"
            replace_placeholders(storage_account_replace_file, storage_account_replacement)
            execute(Path(working_dir), infra_commands)
        else:
            print(f"❌ Unsupported cloud provider: {cloud_provider}")
            return
    except subprocess.CalledProcessError as e:
        print(f"❌ Terraform error:\n{e.stderr}")
    finally:
        # Restore original files
        for original, backup in backups:
            restore_file(original, backup)
        cleanup_terraform_artifacts(Path(working_dir))
        cleanup_terraform_artifacts(remote_state_dir)

def upgrade_terraform_commands(cluster_name, region, cloud_provider, working_dir):
    """
    Run terraform commands in two directories:
    - In remote_state_dir: use a var-file
    - In other_dir: run basic terraform commands
    """
    source_files = ["terraform.tfvars", "main.tf"]
    cluster_clean = re.sub(r'[^A-Za-z0-9]', '', cluster_name)
    replacements = {
        "<cluster_name>": cluster_name,
        "<db_name>": f"{cluster_clean}db",
        "<db_username>": f"{cluster_clean}admin",
        "<region>": region
    }
    backups = []
    def extract_resource_group_name(tf_file):
        with open(tf_file, "r") as f:
            content = f.read()
        match = re.search(r'resource_group\s*=\s*"([^"]+)"', content)
        return match.group(1) if match else None
    
    def get_storage_account_name(resource_group, prefix="tfstate"):
        """Fetch the Azure storage account name by prefix in the given resource group."""
        try:
            result = subprocess.run(
                ["az", "storage", "account", "list", "--resource-group", resource_group, "--query", "[].name", "-o", "json"],
                capture_output=True, text=True, check=True
            )
            accounts = json.loads(result.stdout)
            for acc in accounts:
                if acc.startswith(prefix):
                    return acc
            print(f"⚠️ No storage account found starting with '{prefix}' in resource group '{resource_group}'.")
            return None
        except subprocess.CalledProcessError as e:
            print(f"⚠️ Failed to fetch storage account name: {e}")
            return None
    try:
        for file_name in source_files:
            file_path = Path(working_dir) / file_name
            if file_path.exists():
                path = Path(file_path)
                backup_path = path.with_suffix(".bak")
                # Backup
                shutil.copy(path, backup_path)
                backups.append((file_path, backup_path))
                replace_placeholders(path, replacements)
            else:
                print(f"⚠️ Skipping missing file: {file_name}")

        # Commands for the other dir (basic commands)
        infra_commands = [
            ["terraform", "init"],
            ["terraform", "plan"],
            ["terraform", "apply"]
        ]

        def execute(directory, commands):
            print(f"\n📁 Entering: {directory}")
            for cmd in commands:
                print(f"🔧 Running: {' '.join(cmd)}")
                try:
                    result = subprocess.run(
                        cmd,
                        cwd=directory,
                        check=True
                    )
                    print(f"✅ Output:\n{result.stdout}")
                except subprocess.CalledProcessError as e:
                    print(f"❌ Error running {' '.join(cmd)}:\n{e.stderr}")
                    break  # Stop further execution if one command fails
        cleanup_terraform_artifacts(Path(working_dir))
        if cloud_provider.lower() == "aws":
            execute(Path(working_dir), infra_commands)
        elif cloud_provider.lower() == "azure":
            tf_file = Path(working_dir)/"terraform.tfvars"
            resourcegroup = extract_resource_group_name(tf_file)
            storage_account = get_storage_account_name(resourcegroup)
            storage_account_replacement = {
                "<storage_account>": storage_account
            }
            storage_account_replace_file = Path(working_dir)/"main.tf"
            replace_placeholders(storage_account_replace_file, storage_account_replacement)
            execute(Path(working_dir), infra_commands)
        else:
            print(f"❌ Unsupported cloud provider: {cloud_provider}")
            return
    except subprocess.CalledProcessError as e:
        print(f"❌ Terraform error:\n{e.stderr}")
    finally:
        # Restore original files
        for original, backup in backups:
            restore_file(original, backup)
        cleanup_terraform_artifacts(Path(working_dir))

def terraform_destroy_commands(cluster_name, region, cloud_provider, working_dir="."):
    """
    Run terraform commands in two directories:
    - In remote_state_dir: use a var-file
    - In other_dir: run basic terraform commands
    """
    source_files = ["terraform.tfvars", "main.tf"]
    cluster_clean = re.sub(r'[^A-Za-z0-9]', '', cluster_name)
    replacements = {
        "<cluster_name>": cluster_name,
        "<db_name>": f"{cluster_clean}db",
        "<db_username>": f"{cluster_clean}admin",
        "<region>": region
    }

    def extract_s3_bucket_name(tf_file):
        with open(tf_file, "r") as f:
            content = f.read()
        match = re.search(r'bucket_name\s*=\s*"([^"]+)"', content)
        return match.group(1) if match else None
    
    def extract_environment_name(tf_file):
        with open(tf_file, "r") as f:
            content = f.read()
        match = re.search(r'environment\s*=\s*"([^"]+)"', content)
        return match.group(1) if match else None
    
    def get_storage_account_name(resource_group, prefix="tfstate"):
        """Fetch the Azure storage account name by prefix in the given resource group."""
        try:
            result = subprocess.run(
                ["az", "storage", "account", "list", "--resource-group", resource_group, "--query", "[].name", "-o", "json"],
                capture_output=True, text=True, check=True
            )
            accounts = json.loads(result.stdout)
            for acc in accounts:
                if acc.startswith(prefix):
                    return acc
            print(f"⚠️ No storage account found starting with '{prefix}' in resource group '{resource_group}'.")
            return None
        except subprocess.CalledProcessError as e:
            print(f"⚠️ Failed to fetch storage account name: {e}")
            return None
    
    def delete_azure_storage(storage_account, resource_group, container):
        """Delete blobs, container, storage account, and resource group in Azure."""
        try:
            print(f"🧹 Deleting all blobs in Azure container '{container}' from account '{storage_account}'...")
            subprocess.run([
                "az", "storage", "blob", "delete-batch",
                "--source", container,
                "--account-name", storage_account
            ], check=True)
            print(f"✅ Blobs deleted from container '{container}'.")

            print(f"🗑  Deleting container '{container}'...")
            subprocess.run([
                "az", "storage", "container", "delete",
                "--name", container,
                "--account-name", storage_account
            ], check=True)
            print(f"✅ Container '{container}' deleted.")

            print(f"🗑  Deleting storage account '{storage_account}'...")
            subprocess.run([
                "az", "storage", "account", "delete",
                "--name", storage_account,
                "--resource-group", resource_group,
                "--yes"
            ], check=True)
            print(f"✅ Storage account '{storage_account}' deleted.")

            print(f"🗑  Deleting resource group '{resource_group}'...")
            subprocess.run([
                "az", "group", "delete",
                "--name", resource_group,
                "--yes", "--no-wait"
            ], check=True)
            print(f"✅ Resource group '{resource_group}' scheduled for deletion.")

        except subprocess.CalledProcessError as e:
            print(f"⚠️ Failed to delete Azure storage resources: {e}")
    
    def is_s3_bucket_empty(bucket):
        try:
            result = subprocess.run([
                "aws", "s3api", "list-object-versions",
                "--bucket", bucket,
                "--output", "json"
            ], check=True, stdout=subprocess.PIPE, text=True)

            data = json.loads(result.stdout)
            versions = data.get("Versions", [])
            delete_markers = data.get("DeleteMarkers", [])

            total_items = len(versions) + len(delete_markers)
            return total_items == 0

        except subprocess.CalledProcessError as e:
            print(f"❌ Error checking S3 bucket:\n{e.stderr}")
            return False
        except json.JSONDecodeError as e:
            print(f"❌ JSON parsing error while checking S3 bucket: {e}")
            return False
        
    def delete_s3_and_dynamodb(name):
        print(f"🧹 Deleting resources with name: {name}")

        s3 = boto3.client('s3')
        dynamodb = boto3.client('dynamodb')

        # Step 1: Delete all versions in the S3 bucket
        try:
            print(f"🔸 Emptying S3 bucket: {name}")
            paginator = s3.get_paginator('list_object_versions')
            for page in paginator.paginate(Bucket=name):
                objects = [
                    {'Key': obj['Key'], 'VersionId': obj['VersionId']}
                    for obj in page.get('Versions', []) + page.get('DeleteMarkers', [])
                ]
                if objects:
                    s3.delete_objects(Bucket=name, Delete={'Objects': objects})
            print(f"✅ Emptied S3 bucket: {name}")
        except ClientError as e:
            print(f"⚠️ Skipped S3 deletion: {e.response['Error']['Message']}")

        # Step 2: Delete the S3 bucket itself
        try:
            s3.delete_bucket(Bucket=name)
            print(f"✅ Deleted S3 bucket: {name}")
        except ClientError as e:
            print(f"⚠️ Could not delete bucket: {e.response['Error']['Message']}")

        # Step 3: Delete DynamoDB table
        try:
            print(f"🔸 Deleting DynamoDB table: {name}")
            dynamodb.delete_table(TableName=name)
            waiter = dynamodb.get_waiter('table_not_exists')
            waiter.wait(TableName=name)
            print(f"✅ Deleted DynamoDB table: {name}")
        except ClientError as e:
            print(f"⚠️ Skipped DynamoDB deletion: {e.response['Error']['Message']}")

    backups = []
    try:
        for file_name in source_files:
            file_path = Path(working_dir) / file_name
            if file_path.exists():
                path = Path(file_path)
                backup_path = path.with_suffix(".bak")
                # Backup
                shutil.copy(path, backup_path)
                backups.append((file_path, backup_path))
                replace_placeholders(path, replacements)
            else:
                print(f"⚠️ Skipping missing file: {file_name}")

        # Commands for the other dir (basic commands)
        destroy_commands = [
            ["terraform", "init"],
            ["terraform", "destroy", "-lock=false"]
        ]

        def execute(directory, commands):
            print(f"\n📁 Entering: {directory}")
            for cmd in commands:
                print(f"🔧 Running: {' '.join(cmd)}")
                result = subprocess.run(
                    cmd,
                    cwd=directory,
                    check=True
                )
                print(f"✅ Output:\n{result.stdout}")
            # delete_s3_and_dynamodb(bucket)
        tf_file_path = Path(working_dir)/"terraform.tfvars"
        if cloud_provider.lower() == "aws":
        # === AWS Cleanup ===
            bucket = extract_s3_bucket_name(tf_file_path)
            print(bucket)
            if not bucket:
                print("❌ Could not determine S3 bucket name from remote state main.tf.")
                return
            bucket_empty = is_s3_bucket_empty(bucket)
            if bucket_empty:
                print("📦 Bucket is empty. Proceeding to destroy only in remote state directory.")
                delete_s3_and_dynamodb(bucket)
            else:
                print("📦 Bucket is NOT empty. Proceeding with 2-step destroy.")
                cleanup_terraform_artifacts(Path(working_dir))
                execute(Path(working_dir), destroy_commands)
                delete_s3_and_dynamodb(bucket)
        elif cloud_provider.lower() == "azure":
        # === Azure Cleanup ===
            environment = extract_environment_name(tf_file_path)
            resourcegroup = f"{environment}-rg"
            container     = f"{environment}-container"
            storage_account = get_storage_account_name(resourcegroup)
            if not storage_account or not resourcegroup:
                print("❌ Could not determine Azure Storage Account or Resourcegroup.")
                return

            cleanup_terraform_artifacts(Path(working_dir))
            storage_account_replacement = {
                "<storage_account>": storage_account
            }
            storage_account_replace_file = Path(working_dir)/"main.tf"
            replace_placeholders(storage_account_replace_file, storage_account_replacement)
            execute(Path(working_dir), destroy_commands)
            delete_azure_storage(storage_account, resourcegroup, container)
        else:
            print(f"❌ Unsupported cloud provider: {cloud_provider}")
            return
    except subprocess.CalledProcessError as e:
        print(f"❌ Terraform error:\n{e.stderr}")
    finally:
        # Restore original files
        for original, backup in backups:
            restore_file(original, backup)
        cleanup_terraform_artifacts(Path(working_dir))

def replace_placeholders(path, replacements):
    """Replace placeholders in the given file and backup the original."""
    # path = Path(file_path)
    # backup_path = path.with_suffix(".bak")

    # # Backup
    # shutil.copy(path, backup_path)

    with open(path, "r") as f:
        content = f.read()

    for placeholder, value in replacements.items():
        content = content.replace(placeholder, value)

    with open(path, "w") as f:
        f.write(content)

    print(f"✅ Updated: {path.name}")
    # return backup_path

def restore_file(original_path, backup_path):
    """Restore file from backup."""
    shutil.move(backup_path, original_path)
    print(f"🔁 Restored original: {original_path.name}")

def run_command(command, shell=False, check=True):
    print(f"Running: {' '.join(command) if isinstance(command, list) else command}")
    subprocess.run(command, shell=shell, check=check)

def refresh_sys_path():
    """
    Refresh sys.path to include user site-packages after installing with pip.
    Needed especially if user-level install happens dynamically.
    """
    from site import getusersitepackages
    user_site = getusersitepackages()
    if user_site not in sys.path:
        sys.path.append(user_site)

def ensure_package(pip_name, import_name=None):
    if import_name is None:
        import_name = pip_name
    if importlib.util.find_spec(import_name) is None:
        print(f"Installing missing Python package: {pip_name}")
        run_command([sys.executable, "-m", "pip", "install", pip_name])
        refresh_sys_path()

def install_inquirerPy():
    required = [
        ("InquirerPy", None), 
    ]
    for pip_name, import_name in required:
        ensure_package(pip_name, import_name)
    
    global inquirer
    from InquirerPy import inquirer

def install_boto_and_other_dependencies():
    required = [
        ("boto3", None),
        ("botocore", None),
        ("InquirerPy", None),
        ("PyYAML", "yaml"),  # Example of pip name vs import name
    ]
    for pip_name, import_name in required:
        ensure_package(pip_name, import_name)

def install_homebrew_if_needed():
    try:
        run_command(["brew", "--version"])
        print("Homebrew is already installed.")
    except subprocess.CalledProcessError:
        print("Homebrew not found. Installing Homebrew...")
        run_command(
            '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
        )
        # Add Homebrew to PATH for current script if it's not automatically sourced
        brew_path = "/opt/homebrew/bin/brew"  # Apple Silicon default
        if not shutil.which("brew") and os.path.exists(brew_path):
            os.environ["PATH"] += os.pathsep + "/opt/homebrew/bin"
        print("Homebrew installation completed.")

def install_az_cli():
    os_type = platform.system().lower()

    if os_type == "linux":
        run_command(["curl", "-sL", "https://aka.ms/InstallAzureCLIDeb", "-o", "install.sh"])
        run_command(["chmod", "+x", "install.sh"])
        run_command(["sudo", "./install.sh"])
        run_command(["rm", "-f", "install.sh"])

    elif os_type == "darwin":
        install_homebrew_if_needed()
        run_command(["brew", "update"])
        run_command(["brew", "install", "azure-cli"])
    else:
        print(f"Azure CLI installation not supported for {os_type}")

def install_aws_cli():
    os_type = platform.system().lower()

    if os_type == "linux":
        run_command([
            "curl", "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip", "-o", "awscliv2.zip"
        ])
        run_command(["unzip", "-o", "awscliv2.zip"])
        run_command(["sudo", "./aws/install", "--update"])
        run_command(["rm", "-rf", "awscliv2.zip", "aws/"])
    elif os_type == "darwin":
        run_command([
            "curl", "https://awscli.amazonaws.com/AWSCLIV2.pkg", "-o", "AWSCLIV2.pkg"
        ])
        run_command(["sudo", "installer", "-pkg", "AWSCLIV2.pkg", "-target", "/"])
        run_command(["rm", "AWSCLIV2.pkg"])
    else:
        print(f"AWS CLI installation not supported for {os_type}")

def install_git():
    import os

    def get_distro():
        try:
            with open("/etc/os-release") as f:
                data = f.read()
                if "ubuntu" in data.lower():
                    return "ubuntu"
                elif "debian" in data.lower():
                    return "debian"
                elif "amzn" in data.lower() or "amazon" in data.lower():
                    return "amazon"
                elif "centos" in data.lower():
                    return "centos"
                elif "alpine" in data.lower():
                    return "alpine"
                elif "red hat" in data.lower():
                    return "rhel"
        except FileNotFoundError:
            pass
        return "unknown"

    distro = get_distro()

    try:
        if distro in ("ubuntu", "debian"):
            run_command(["sudo", "apt", "update"])
            run_command(["sudo", "apt", "install", "-y", "git"])
        elif distro in ("amazon", "centos", "rhel"):
            run_command(["sudo", "yum", "install", "-y", "git"])
        elif distro == "alpine":
            run_command(["sudo", "apk", "add", "git"])
        else:
            raise RuntimeError(f"Unsupported Linux distro: {distro}")
    except Exception as e:
        print(f"Error installing Git: {e}")
        sys.exit(1)
def install_terraform():
    os_type = platform.system().lower()
    arch = platform.machine().lower()
    arch = "amd64" if "x86_64" in arch else arch

    terraform_version = "1.8.5"  # update as needed
    tf_zip = f"terraform_{terraform_version}_{os_type}_{arch}.zip"
    url = f"https://releases.hashicorp.com/terraform/{terraform_version}/{tf_zip}"

    run_command(["curl", "-o", tf_zip, url])
    run_command(["unzip", "-o", tf_zip])
    run_command(["sudo", "mv", "terraform", "/usr/local/bin/terraform"])
    run_command(["rm", tf_zip])

def import_from_different_folder(module_path, module_name):
    spec = importlib.util.spec_from_file_location(module_name, module_path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[module_name] = module
    spec.loader.exec_module(module)
    return module

def ensure_azure_dependencies():
    # -- Import your Azure-specific logic from another folder --
    AZURE_MODULE_PATH = "sample-azure/azure_credentials.py"  # <-- UPDATE THIS
    azure_iam = import_from_different_folder(AZURE_MODULE_PATH, "azure_credentials")

    # Optional: make functions available globally if needed like you did for AWS
    global select_or_create_profile, set_azure_env, get_current_sp_object_id, check_permissions, validate_azure_location
    select_or_create_profile = azure_iam.select_or_create_profile
    set_azure_env = azure_iam.set_azure_env
    get_current_sp_object_id = azure_iam.get_current_sp_object_id
    check_permissions = azure_iam.check_permissions
    validate_azure_location = azure_iam.validate_azure_location

    # -- Ensure az CLI --
    try:
        subprocess.run(["az", "--version"], check=True, stdout=subprocess.DEVNULL)
        print("Azure CLI already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Installing Azure CLI...")
        install_az_cli()

    # -- Ensure Terraform --
    try:
        subprocess.run(["terraform", "-version"], check=True, stdout=subprocess.DEVNULL)
        print("Terraform already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Installing Terraform...")
        install_terraform()

    # -- Ensure Git --
    try:
        subprocess.run(["git", "--version"], check=True, stdout=subprocess.DEVNULL)
        print("Git already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Installing Git...")
        install_git()

def ensure_aws_dependencies():
    import importlib.util

    install_boto_and_other_dependencies()
    AWS_MODULE_PATH = "sample-aws/aws_iam.py"  # <-- UPDATE THIS
    aws_iam = import_from_different_folder(AWS_MODULE_PATH, "aws_iam")

    global boto3,botocore,yaml,get_aws_inputs_and_validate,simulate_permissions,load_actions_from_yaml,Spinner,print_results,ProfileNotFound,setup_session
    import boto3
    import botocore
    import yaml
    from botocore.exceptions import ClientError
    from botocore.exceptions import ProfileNotFound
    get_aws_inputs_and_validate = aws_iam.get_aws_inputs_and_validate
    simulate_permissions = aws_iam.simulate_permissions
    load_actions_from_yaml = aws_iam.load_actions_from_yaml
    Spinner = aws_iam.Spinner
    print_results = aws_iam.print_results
    setup_session = aws_iam.setup_session

    try:
        subprocess.run(["aws", "--version"], check=True, stdout=subprocess.DEVNULL)
        print("AWS CLI already installed.")
    except subprocess.CalledProcessError:
        print("Installing AWS CLI...")
        install_aws_cli()

    try:
        subprocess.run(["terraform", "-version"], check=True, stdout=subprocess.DEVNULL)
        print("Terraform already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Installing Terraform...")
        install_terraform()
    try:
        subprocess.run(["git", "--version"], check=True, stdout=subprocess.DEVNULL)
        print("Git already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Installing Git...")
        install_git()


def main():
    parser = argparse.ArgumentParser(description="Manage Terraform infrastructure.")
    parser.add_argument('--create', action='store_true', help='Create infrastructure')
    parser.add_argument('--upgrade', action='store_true', help='Upgrade infrastructure')
    parser.add_argument('--destroy', action='store_true', help='Destroy infrastructure')
    args = parser.parse_args()
    install_inquirerPy()
    os.environ.pop('AWS_PROFILE', None)
    cloud_choice = inquirer.select(
        message="Choose your cloud provider:",
        choices=[
            {"name": "AWS", "value": "aws"},
            {"name": "Azure ", "value": "azure"},
            {"name": "GCP (coming soon)", "value": "gcp"},
        ],
    ).execute()
    if args.create:
        if cloud_choice == "aws":
            ensure_aws_dependencies()
            config = get_aws_inputs_and_validate()
            actions = load_actions_from_yaml('permissions.yaml')
            cluster_name = input("Enter the Cluster Name: ")
            spinner = Spinner()
            spinner.start()
            results = simulate_permissions(config['session'], actions, cluster_name)
            spinner.stop()
            print_results(results)
            print("\n--- AWS Configuration Complete ---")
            for k, v in config.items():
                if k != "session" and k!= "profile":
                    print(f"{k}: {v}")
            print("\n...Configuring Infra...")
            setup_session(config['profile'], config['region'])
            run_terraform_commands(cluster_name, config['region'])
        elif cloud_choice == "azure":
            ensure_azure_dependencies()
            print("🚀 Azure Credential & Permission Validator")
            selected_profile = select_or_create_profile()
            region = input("Enter the Region Name: ")
            validate_azure_location(region)
            cluster_name = input("Enter the Cluster Name: ")
            set_azure_env(selected_profile)
            object_id = get_current_sp_object_id(selected_profile)
            check_permissions(object_id)
            run_terraform_commands(cluster_name, region, cloud_choice, "sample-azure")
        else:
            print("Only AWS and Azure is currently supported. Others coming soon!")
    elif args.destroy:
        if cloud_choice == "aws":
            ensure_aws_dependencies()
            config = get_aws_inputs_and_validate()
            actions = load_actions_from_yaml('permissions.yaml')
            cluster_name = input("Enter the Cluster Name: ")
            spinner = Spinner()
            spinner.start()
            results = simulate_permissions(config['session'], actions, cluster_name)
            spinner.stop()
            print_results(results)
            print("\n--- AWS Configuration Complete ---")
            for k, v in config.items():
                if k != "session" and k!= "profile":
                    print(f"{k}: {v}")
            print("\n...Destroying Infra...")
            setup_session(config['profile'], config['region'])
            terraform_destroy_commands(cluster_name, config['region'])
        elif cloud_choice == "azure":
            ensure_azure_dependencies()
            print("🚀 Azure Credential & Permission Validator")
            selected_profile = select_or_create_profile()
            region = input("Enter the Region Name: ")
            validate_azure_location(region)
            cluster_name = input("Enter the Cluster Name: ")
            set_azure_env(selected_profile)
            object_id = get_current_sp_object_id(selected_profile)
            check_permissions(object_id)
            terraform_destroy_commands(cluster_name, region, cloud_choice, "sample-azure")
        else:
            print("Only AWS and Azure is currently supported. Others coming soon!")
    elif args.upgrade:
        if cloud_choice == "aws":
            ensure_aws_dependencies()
            config = get_aws_inputs_and_validate()
            actions = load_actions_from_yaml('permissions.yaml')
            cluster_name = input("Enter the Cluster Name: ")
            spinner = Spinner()
            spinner.start()
            results = simulate_permissions(config['session'], actions, cluster_name)
            spinner.stop()
            print_results(results)
            print("\n--- AWS Configuration Complete ---")
            for k, v in config.items():
                if k != "session":
                    print(f"{k}: {v}")
            print("\n...Upgrading Infra...")
            setup_session(config['profile'], config['region'])
            upgrade_terraform_commands(cluster_name, config['region'])
        elif cloud_choice == "azure":
            ensure_azure_dependencies()
            print("🚀 Azure Credential & Permission Validator")
            selected_profile = select_or_create_profile()
            region = input("Enter the Region Name: ")
            validate_azure_location(region)
            cluster_name = input("Enter the Cluster Name: ")
            set_azure_env(selected_profile)
            object_id = get_current_sp_object_id(selected_profile)
            check_permissions(object_id)
            upgrade_terraform_commands(cluster_name, region, cloud_choice, "sample-azure")
        else:
            print("Only AWS and Azure is currently supported. Others coming soon!")
    else:
        print("❗ Please specify --create or --destroy")


if __name__ == "__main__":
    main()                                                                                                                                                        