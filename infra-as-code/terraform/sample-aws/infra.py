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

def run_terraform_commands(cluster_name, region,working_dir="."):
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
    try:
        for file_name in source_files:
            file_path = Path(working_dir) / file_name
            if file_path.exists():
                backup_path = replace_placeholders(file_path, replacements)
                backups.append((file_path, backup_path))
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
        execute(Path(working_dir), infra_commands)
    except subprocess.CalledProcessError as e:
        print(f"❌ Terraform error:\n{e.stderr}")
    finally:
        # Restore original files
        for original, backup in backups:
            restore_file(original, backup)
        cleanup_terraform_artifacts(Path(working_dir))
        cleanup_terraform_artifacts(remote_state_dir)

def upgrade_terraform_commands(cluster_name, region,working_dir="."):
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
    try:
        for file_name in source_files:
            file_path = Path(working_dir) / file_name
            if file_path.exists():
                backup_path = replace_placeholders(file_path, replacements)
                backups.append((file_path, backup_path))
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
        execute(Path(working_dir), infra_commands)
    except subprocess.CalledProcessError as e:
        print(f"❌ Terraform error:\n{e.stderr}")
    finally:
        # Restore original files
        for original, backup in backups:
            restore_file(original, backup)
        cleanup_terraform_artifacts(Path(working_dir))

def terraform_destroy_commands(cluster_name, region,working_dir="."):
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
                backup_path = replace_placeholders(file_path, replacements)
                backups.append((file_path, backup_path))
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
            # delete_s3_and_dynamodb(bucket)
        tf_file_path = "terraform.tfvars"
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
    except subprocess.CalledProcessError as e:
        print(f"❌ Terraform error:\n{e.stderr}")
    finally:
        # Restore original files
        for original, backup in backups:
            restore_file(original, backup)
        cleanup_terraform_artifacts(Path(working_dir))

def replace_placeholders(file_path, replacements):
    """Replace placeholders in the given file and backup the original."""
    path = Path(file_path)
    backup_path = path.with_suffix(".bak")

    # Backup
    shutil.copy(path, backup_path)

    with open(path, "r") as f:
        content = f.read()

    for placeholder, value in replacements.items():
        content = content.replace(placeholder, value)

    with open(path, "w") as f:
        f.write(content)

    print(f"✅ Updated: {path.name}")
    return backup_path

def restore_file(original_path, backup_path):
    """Restore file from backup."""
    shutil.move(backup_path, original_path)
    print(f"🔁 Restored original: {original_path.name}")

def run_command(command, shell=False, check=True):
    print(f"Running: {' '.join(command) if isinstance(command, list) else command}")
    subprocess.run(command, shell=shell, check=check)
def ensure_package(pip_name, import_name=None):
    if import_name is None:
        import_name = pip_name
    if importlib.util.find_spec(import_name) is None:
        print(f"Installing missing Python package: {pip_name}")
        run_command([sys.executable, "-m", "pip", "install", pip_name])

def install_boto_and_other_dependencies():
    required = [
        ("boto3", None),
        ("botocore", None),
        ("InquirerPy", None),
        ("PyYAML", "yaml"),  # Example of pip name vs import name
    ]
    for pip_name, import_name in required:
        ensure_package(pip_name, import_name)

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

def ensure_aws_dependencies():
    import importlib.util

    install_boto_and_other_dependencies()

    global boto3,botocore,inquirer,yaml,get_aws_inputs_and_validate,simulate_permissions,load_actions_from_yaml,Spinner,print_results,ProfileNotFound,setup_session
    import boto3
    import botocore
    import yaml
    from InquirerPy import inquirer
    from aws_iam import get_aws_inputs_and_validate
    from aws_iam import simulate_permissions
    from aws_iam import load_actions_from_yaml
    from aws_iam import Spinner
    from aws_iam import print_results
    from aws_iam import setup_session
    from botocore.exceptions import ClientError
    from botocore.exceptions import ProfileNotFound

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
    ensure_aws_dependencies()
    os.environ.pop('AWS_PROFILE', None)
    cloud_choice = inquirer.select(
        message="Choose your cloud provider:",
        choices=[
            {"name": "AWS", "value": "aws"},
            {"name": "Azure (coming soon)", "value": "azure"},
            {"name": "GCP (coming soon)", "value": "gcp"},
        ],
    ).execute()
    if args.create:
        if cloud_choice == "aws":
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
        else:
            print("Only AWS is currently supported. Others coming soon!")
    elif args.destroy:
        if cloud_choice == "aws":
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
        else:
            print("Only AWS is currently supported. Others coming soon!")
    elif args.upgrade:
        if cloud_choice == "aws":
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
        else:
            print("Only AWS is currently supported. Others coming soon!")
    else:
        print("❗ Please specify --create or --destroy")


if __name__ == "__main__":
    main()                                                                                                                                                        