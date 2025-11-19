#!/usr/bin/env python3
import os
import platform
import subprocess
import sys
import argparse
from datetime import datetime
import requests
from pathlib import Path
import zipfile
import io
import importlib.util
import shutil
import re
import json
from InquirerPy import inquirer

GITHUB_USER = "egovernments"
REPO_NAME = "DIGIT-DevOps"
BRANCH = "digit-automation"
GITHUB_BASE_URL = f"https://github.com/{GITHUB_USER}/{REPO_NAME}/archive/refs/heads/{BRANCH}.zip"

def run_command(command, cwd=None, shell=False, check=True, input=None, ignore_error=False):
    """Execute shell commands cleanly."""
    try:
        print(f"Running: {' '.join(command) if isinstance(command, list) else command}")
        subprocess.run(command, shell=shell, check=check, input=input)
    except subprocess.CalledProcessError as e:
        if ignore_error:
            return
        print(f"❌ Failed to run command: {' '.join(command) if isinstance(command, list) else command}")
        print(f"Reason: {e}")
        sys.exit(1)
    except FileNotFoundError:
        if ignore_error:
            return
        print(f"❌ Command not found: {command[0] if isinstance(command, list) else command}")
        sys.exit(1)

def refresh_sys_path():
    """
    Refresh sys.path to include user site-packages after installing with pip.
    Needed especially if user-level install happens dynamically.
    """
    from site import getusersitepackages
    user_site = getusersitepackages()
    if user_site not in sys.path:
        sys.path.append(user_site)



def check_prerequisites():
    for cmd in ["curl", "unzip", "sudo"]:
        if shutil.which(cmd) is None:
            print(f"❌ Required tool '{cmd}' not found. Please install it manually.")
            sys.exit(1)

def import_from_file(file_path: str, module_name: str):
    """
    Import a Python script dynamically from any folder.
    file_path: absolute or relative path to .py file
    module_name: name to assign to the module
    """
    file_path = Path(file_path).resolve()
    if not file_path.exists():
        raise FileNotFoundError(f"Module file not found: {file_path}")

    spec = importlib.util.spec_from_file_location(module_name, str(file_path))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def ensure_aws_dependencies(run_dir):
    """
    Ensure AWS CLI, Terraform, Git, and AWS module scripts are available
    """
    # 1️⃣ Path to aws_iam.py inside the extracted sample folder
    aws_module_path = Path(run_dir) / f"{REPO_NAME}-{BRANCH}/infra-as-code/terraform/sample-aws/aws_iam.py"
    
    # 2️⃣ Import dynamically
    aws_iam = import_from_file(aws_module_path, "aws_iam")

    # 3️⃣ Expose required functions/classes globally if needed
    global boto3,botocore,yaml,get_aws_inputs_and_validate,simulate_permissions,load_actions_from_yaml,Spinner,print_results,ProfileNotFound,setup_session, ClientError
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

    # 5️⃣ Ensure CLI tools installed
    aws_path = shutil.which("aws")
    if not aws_path:
        print("❌ AWS CLI not found.")
        print("Please install AWS CLI v2 and ensure it is available in your PATH.")
        print("👉 Installation guide: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html")
        sys.exit(1)

    try:
        result = subprocess.run(["aws", "--version"], capture_output=True, text=True, check=True)
        version_output = (result.stdout or "") + (result.stderr or "")
        if "aws-cli/2" in version_output:
            print("✅ AWS CLI v2 detected.")
        elif "aws-cli/1" in version_output:
            print("❌ AWS CLI v1 detected. Please uninstall v1 and install v2.")
            sys.exit(1)
        else:
            print("⚠️ Unable to determine AWS CLI version. Proceeding with caution.")
    except (subprocess.CalledProcessError, FileNotFoundError, OSError) as e:
        print(f"❌ Error checking AWS CLI version: {e}")
        print("Please verify AWS CLI installation.")
        sys.exit(1)
    try:
        subprocess.run(["terraform", "-version"], check=True, stdout=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Please install the Terraform...")
        sys.exit(1)

    try:
        subprocess.run(["git", "--version"], check=True, stdout=subprocess.DEVNULL)
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Please Install the Git...")
        sys.exit(1)

def ensure_azure_dependencies(run_dir):
    AZURE_MODULE_PATH = Path(run_dir) / f"{REPO_NAME}-{BRANCH}/infra-as-code/terraform/sample-azure/azure_credentials.py"  # <-- UPDATE THIS
    azure_iam = import_from_file(AZURE_MODULE_PATH, "azure_credentials")

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
        print("Please install the Azure CLI...")
        sys.exit(1)

    # -- Ensure Terraform --
    check_prerequisites()
    try:
        subprocess.run(["terraform", "-version"], check=True, stdout=subprocess.DEVNULL)
        print("Terraform already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Please install the Terraform...")
        sys.exit(1)

    # -- Ensure Git --
    try:
        subprocess.run(["git", "--version"], check=True, stdout=subprocess.DEVNULL)
        print("Git already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Please Install the Git...")
        sys.exit(1)

def ensure_gcp_dependencies(run_dir):
    """Check if gcloud is installed, otherwise install it"""
    try:
        subprocess.run(["gcloud", "--version"], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("✅ Google Cloud CLI already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Please install Google Cloud CLI...")
        sys.exit(1)
    # -- Ensure Terraform --
    check_prerequisites()
    try:
        subprocess.run(["terraform", "-version"], check=True, stdout=subprocess.DEVNULL)
        print("Terraform already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Please install the Terraform...")
        sys.exit(1)

    # -- Ensure Git --
    try:
        subprocess.run(["git", "--version"], check=True, stdout=subprocess.DEVNULL)
        print("Git already installed.")
    except (subprocess.CalledProcessError, FileNotFoundError):
        print("Please Install the Git...")
        sys.exit(1)
    # -- Import your GCP-specific logic from another folder --
    import PyYAML
    import yaml
    GCP_MODULE_PATH = Path(run_dir) / f"{REPO_NAME}-{BRANCH}/infra-as-code/terraform/sample-gcp/gcp-iam.py"  # <-- UPDATE THIS
    gcp_iam = import_from_file(GCP_MODULE_PATH, "gcp-iam")

    # Optional: make functions available globally if needed like you did for AWS
    global gcp_main, project_id, region_name, zone
    gcp_main = gcp_iam.gcp_main()
    project_id = gcp_iam.get_project_id()
    region_name, zone = gcp_iam.fetch_region_zone()

def download_deployment_files(owner, repo, branch, paths, dest_dir):
    """
    Downloads specific files or folders from a GitHub repository using the GitHub Contents API.
    Gracefully exits if any download step fails.
    """
    base_url = f"https://api.github.com/repos/{owner}/{repo}/contents"
    dest_dir = Path(dest_dir)
    dest_dir.mkdir(parents=True, exist_ok=True)

    print(f"📥 Downloading from {repo}@{branch} → {dest_dir}\n")

    for path in paths:
        path = path.strip().rstrip('/')  # remove trailing slash if any
        url = f"{base_url}/{path}?ref={branch}"

        try:
            resp = requests.get(url, timeout=20)
            resp.raise_for_status()
        except requests.exceptions.RequestException as e:
            print(f"❌ Network error while fetching {path}: {e}")
            sys.exit(1)

        try:
            data = resp.json()
        except ValueError:
            print(f"❌ Failed to parse GitHub API response for {path}.")
            sys.exit(1)

        # If API returned an error message
        if isinstance(data, dict) and data.get("message"):
            print(f"❌ Failed to fetch {path}: {data['message']} (Status: {resp.status_code})")
            sys.exit(1)

        # Case 1: Folder → iterate through contents
        if isinstance(data, list):
            folder_path = dest_dir / path
            folder_path.mkdir(parents=True, exist_ok=True)
            for item in data:
                if item["type"] == "file":
                    download_file(item["download_url"], folder_path / item["name"])
                elif item["type"] == "dir":
                    # recursively handle subdirectories
                    download_deployment_files(owner, repo, branch, [item["path"]], dest_dir)
            print(f"✅ Folder '{path}' downloaded successfully.\n")

        # Case 2: Single File
        elif isinstance(data, dict) and data.get("type") == "file":
            download_file(data["download_url"], dest_dir / data["name"])
            print(f"✅ File '{data['name']}' downloaded successfully.\n")

        else:
            print(f"❌ Unexpected response structure while fetching {path}")
            sys.exit(1)

    print("🎉 All specified GitHub content fetched successfully.\n")


def download_file(file_url, dest_path):
    """Helper to download a single file from GitHub raw URL."""
    try:
        r = requests.get(file_url, timeout=20)
        r.raise_for_status()
        with open(dest_path, 'wb') as f:
            f.write(r.content)
    except requests.exceptions.RequestException as e:
        print(f"❌ Failed to download file: {file_url}")
        print(f"   Error: {e}")
        # Cleanup partial file if created
        if os.path.exists(dest_path):
            os.remove(dest_path)
        sys.exit(1)


def create_run_directory(cluster_name: str) -> Path:
    """Create ./runs/<clustername>/<timestamp> directory"""
    timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
    run_dir = Path(f"./runs/{cluster_name}/{timestamp}")
    run_dir.mkdir(parents=True, exist_ok=True)
    print(f"✅ Created run directory: {run_dir}")
    return run_dir


def download_github_zip():
    """Download GitHub repo zip for the branch"""
    print("⬇️  Downloading DIGIT-DevOps repository...")
    try:
        response = requests.get(GITHUB_BASE_URL, timeout=60)
        response.raise_for_status()
        print("✅ Repository downloaded successfully.")
        return zipfile.ZipFile(io.BytesIO(response.content))
    except requests.exceptions.RequestException as e:
        raise RuntimeError(f"[Step: Download Repo] ❌ Failed to download from GitHub: {e}")


def find_module_dirs(zip_ref):
    """List all module directories under infra-as-code/terraform/modules/"""
    top_prefix = f"{REPO_NAME}-{BRANCH}/infra-as-code/terraform/modules/"
    modules = set()
    for member in zip_ref.namelist():
        if member.startswith(top_prefix) and member != top_prefix:
            parts = member.split("/")
            if len(parts) > 5:
                modules.add(parts[4])
    return sorted(list(modules))


def extract_cloud_modules(zip_ref, extract_dir, cloud):
    """Extract only modules that contain the given cloud subfolder"""
    print(f"⚙️  Extracting Terraform modules for cloud: {cloud}")
    modules_dir_prefix = f"{REPO_NAME}-{BRANCH}/infra-as-code/terraform/modules/"
    sample_dir_prefix = f"{REPO_NAME}-{BRANCH}/infra-as-code/terraform/sample-{cloud}"

    modules = find_module_dirs(zip_ref)
    extracted = []

    for module in modules:
        cloud_path = f"{modules_dir_prefix}{module}/{cloud}/"
        if any(m.startswith(cloud_path) for m in zip_ref.namelist()):
            for member in zip_ref.namelist():
                if member.startswith(cloud_path):
                    zip_ref.extract(member, extract_dir)
            extracted.append(f"{module}/{cloud}")

    # Extract sample-<cloud>
    if any(m.startswith(sample_dir_prefix) for m in zip_ref.namelist()):
        for member in zip_ref.namelist():
            if member.startswith(sample_dir_prefix):
                zip_ref.extract(member, extract_dir)
        extracted.append(f"sample-{cloud}")

    if extracted:
        print(f"✅ Extracted modules: {', '.join(extracted)}")
    else:
        print(f"⚠️  No modules found for cloud '{cloud}'.")

def check_aws_existing_resources(session, cluster_name, region, bucket_name=None):
    """
    Checks existing AWS resources (EKS, RDS, VPC).
    - If bucket_name is None → normal create mode (no state comparison)
    - If bucket_name is provided → upgrade mode (compare with Terraform state)
    """
    print(f"🔍 Checking existing resources in region {region} for cluster '{cluster_name}'...")
    existing = {}
    state_resources = set()

    eks = session.client("eks", region_name=region)
    rds = session.client("rds", region_name=region)
    ec2 = session.client("ec2", region_name=region)

    # -------------------------------------------------------------------------
    # 1️⃣ If upgrade mode → Fetch terraform state from S3
    # -------------------------------------------------------------------------
    if bucket_name:
        s3 = session.client("s3", region_name=region)
        state_key = "terraform-setup/terraform.tfstate"  # adjust if your structure differs
        state_resources = {"vpcs": [], "eks_clusters": [], "rds_instances": []}
        try:
            print(f"📦 Fetching Terraform state from bucket '{bucket_name}'...")
            obj = s3.get_object(Bucket=bucket_name, Key=state_key)
            data = json.loads(obj["Body"].read().decode("utf-8"))
        except ClientError as e:
            if e.response["Error"]["Code"] == "NoSuchKey":
                print(f"⚠️ No terraform state found for {cluster_name} in bucket {bucket_name}.")
            else:
                print(f"⚠️ Error fetching terraform state: {e}")
            return state_resources
        for res in data.get("resources", []):
            res_type = res.get("type")
            for instance in res.get("instances", []):
                attrs = instance.get("attributes", {})

                if res_type == "aws_vpc":
                    vpc_id = attrs.get("id")
                    if vpc_id:
                        state_resources["vpcs"].append(vpc_id)

                elif res_type == "aws_eks_cluster":
                    name = attrs.get("name")
                    if name:
                        state_resources["eks_clusters"].append(name)

                elif res_type == "aws_db_instance":
                    db_id = attrs.get("id") or attrs.get("db_instance_identifier")
                    if db_id:
                        state_resources["rds_instances"].append(db_id)

        total = sum(len(v) for v in state_resources.values())
        print(f"✅ Found {total} managed resources in Terraform state.")
        return state_resources

    # -------------------------------------------------------------------------
    # 2️⃣ Check actual AWS resources
    # -------------------------------------------------------------------------
    try:
        clusters = eks.list_clusters()["clusters"]
        matches = [c for c in clusters if cluster_name in c]
        if matches:
            existing["eks_clusters"] = matches
    except ClientError as e:
        print(f"⚠️ Error checking EKS clusters: {e}")

    try:
        db_name = f"{cluster_name}-db"
        instances = rds.describe_db_instances()["DBInstances"]
        matches = [i["DBInstanceIdentifier"] for i in instances if db_name in i["DBInstanceIdentifier"]]
        if matches:
            existing["rds_instances"] = matches
    except ClientError as e:
        print(f"⚠️ Error checking RDS instances: {e}")

    try:
        vpcs = ec2.describe_vpcs()["Vpcs"]
        matches = [
            v["VpcId"]
            for v in vpcs
            if "Tags" in v and any(cluster_name in t.get("Value", "") for t in v["Tags"])
        ]
        if matches:
            existing["vpcs"] = matches
    except ClientError as e:
        print(f"⚠️ Error checking VPCs: {e}")

    # -------------------------------------------------------------------------
    # 3️⃣ Compare & Handle Results
    # -------------------------------------------------------------------------
    if not existing:
        print("✅ No existing conflicting resources found.")
        return

    # --- Create mode ---
    if not bucket_name:
        print("⚠️ Existing resources found:")
        for k, v in existing.items():
            print(f"  - {k}: {', '.join(v)}")

        user_input = input("\nDo you want to continue and recreate (y/n)? ").strip().lower()
        if user_input != "y":
            print("❌ Operation cancelled to prevent resource conflicts.")
            sys.exit(1)
        return

    # --- Upgrade mode ---
    print(f"state resources: {state_resources}")
    print(f"existing resources: {existing}")
    unmanaged = {}
    for res_type, res_list in existing.items():
        state_list = state_resources.get(res_type, [])
        filtered = [r for r in res_list if r not in state_list]
        if filtered:
            unmanaged[res_type] = filtered

    if unmanaged:
        print("\n⚠️ Existing unmanaged resources found (not in Terraform state):")
        for k, v in unmanaged.items():
            print(f"  - {k}: {', '.join(v)}")

        user_input = input("\nDo you want to continue and re-import/recreate (y/n)? ").strip().lower()
        if user_input != "y":
            print("❌ Operation cancelled to prevent resource conflicts.")
            sys.exit(1)
    else:
        print("✅ All existing resources are already tracked in Terraform state.")

def fetch_s3_bucket_from_api(cluster_name, aws_session):
    """Fetch S3 bucket created for Terraform remote state using an existing AWS session."""
    s3 = aws_session.client("s3")
    all_buckets = s3.list_buckets().get("Buckets", [])
    
    # Match buckets like: <cluster_name>-s3-state-xxxxxx
    pattern = re.compile(f"^{cluster_name}-s3-state-[a-f0-9]{{6}}$")
    matched_buckets = [b['Name'] for b in all_buckets if pattern.match(b['Name'])]

    if not matched_buckets:
        print(f"❌ No S3 bucket found for cluster '{cluster_name}' with expected pattern.")
        exit(1)

    if len(matched_buckets) == 1:
        print(f"✅ Found S3 bucket: {matched_buckets[0]}")
        return matched_buckets[0]

    # Multiple buckets found — ask user to select
    question = [
        inquirer.List(
            "bucket",
            message="Multiple S3 buckets found. Please select the bucket for remote state:",
            choices=matched_buckets,
        )
    ]
    answer = inquirer.prompt(question)
    return answer["bucket"] if answer else None

def update_main_backend_with_bucket(work_dir, bucket_name, region):
    """Replace <s3_state_bucket> placeholders in main.tf with the actual bucket name"""
    main_tf_path = Path(work_dir) / "main.tf"
    if not main_tf_path.exists():
        print(f"❌ main.tf not found at {main_tf_path}")
        exit(1)

    content = main_tf_path.read_text()
    new_content = (
        content.replace("<s3_state_bucket>", bucket_name)
               .replace("<region>", region)
    )
    main_tf_path.write_text(new_content)
    print(f"✅ Updated main.tf backend with bucket: {bucket_name} and region: {region}")

def create_tfvars_file(output_path, cloud, base_vars, extra_vars=None):
    """
    Creates a terraform.tfvars file at the given path with the provided variables.
    Supports both default base vars and user-supplied overrides.
    """
    tfvars = base_vars.copy()

    # Merge CLI vars (override base if same key)
    if extra_vars:
        for v in extra_vars:
            if "=" not in v:
                print(f"⚠️ Skipping invalid var '{v}' (must be key=value)")
                continue
            key, value = v.split("=", 1)
            tfvars[key.strip()] = value.strip()

    try:
        with open(output_path, "w") as f:
            for k, v in tfvars.items():
                # Quote strings unless they look like bools or numbers
                if isinstance(v, str) and not re.match(r"^(true|false|\d+)$", v, re.IGNORECASE):
                    f.write(f'{k} = "{v}"\n')
                else:
                    f.write(f"{k} = {v}\n")
        print(f"✅ Created {output_path} for {cloud}")
    except Exception as e:
        print(f"❌ Failed to create {output_path}: {e}")
        sys.exit(1)


def generate_tfvars_for_cloud(cloud, base_dir, config, extra_vars):
    """
    Given a cloud name and base directory, generate terraform.tfvars files
    for both 'remote-state' and 'main' directories.
    """

    cloud = cloud.lower()
    print(f"\n🌩️  Generating terraform.tfvars for {cloud.upper()}")

    if cloud == "aws":
        base_vars = {
            "cluster_name": config.get("cluster_name", "demo"),
            "region": config.get("region", "us-east-1")
        }
    elif cloud == "azure":
        environment = config.get("environment", "demo")
        base_vars = {
            "environment": environment,
            "location": config.get("location", "southindia"),
            "resource_group": f"{environment}-rg"
        }
    elif cloud == "gcp":
        base_vars = {
            "env_name": config.get("env_name", "dev"),
            "region": config.get("region", "us-central1"),
            "zone": config.get("zone", "us-central1-a")
        }
    else:
        print(f"❌ Unknown cloud provider: {cloud}")
        sys.exit(1)

    # Define dirs
    remote_state_dir = Path(base_dir) / "remote-state"
    main_dir = Path(base_dir)

    # Create terraform.tfvars in both dirs
    create_tfvars_file(remote_state_dir / "terraform.tfvars", cloud, base_vars)
    create_tfvars_file(main_dir / "terraform.tfvars", cloud, base_vars, extra_vars)


def get_deployment_choices(branch=None):
    from InquirerPy.base.control import Choice
    from packaging import version

    # --- Ask for branch if not provided ---
    if not branch:
        branch = input("🌿 Enter GitHub branch to fetch Helm modules from (default: automation): ").strip() or "automation"

    print(f"\n🌐 Fetching available Helm modules and versions from branch '{branch}'...")

    base_url = f"https://api.github.com/repos/egovernments/helm-charts/contents/helmfiles?ref={branch}"
    resp = requests.get(base_url)
    if resp.status_code != 200:
        print(f"❌ Failed to fetch modules list: {resp.text}")
        return [], []

    modules = [item["name"] for item in resp.json() if item["type"] == "dir"]

    # Skip backbone from manual selection, add Exit
    selectable_modules = [m for m in modules if m.lower() != "backbone"]
    selectable_modules.append("Exit")

    selected_modules = []

    print("\n📦 Use ↑/↓ to navigate, Space to toggle selections. Choose 'Exit' to confirm and continue.\n")

    while True:
        current_choices = []
        for m in selectable_modules:
            checked = m in selected_modules
            current_choices.append(Choice(value=m, name=m, enabled=checked))

        chosen = inquirer.checkbox(
            message="Select one or more Helm modules to deploy:",
            choices=current_choices,
            instruction="(Use ↑/↓ to navigate, Click Space to select/unselect, choose Exit to confirm)",
            transformer=lambda result: ", ".join(result),
        ).execute()

        # --- Handle Exit explicitly ---
        if "Exit" in chosen:
            chosen.remove("Exit")
            print("🚪 Exit selected — finalizing your selected modules.")
            selected_modules = chosen
            break

        # Keep track of what’s selected so far
        selected_modules = [m for m in chosen if m != "Exit"]

        print(f"✅ Currently selected modules: {', '.join(selected_modules) or 'None yet'}\n")
        print("👉 Continue selecting or choose 'Exit' to confirm.\n")

    # --- If no modules were selected, continue gracefully ---
    if not selected_modules:
        print("⚙️ No modules selected. Continuing without module-based deployment.")
        return [], []

    # --- Always include backbone (auto-select latest version) ---
    if "backbone" not in selected_modules:
        selected_modules.insert(0, "backbone")

    selected_versions = []

    for module in selected_modules:
        print(f"\n📦 Fetching helmfile versions for module: {module}")
        version_url = f"https://api.github.com/repos/egovernments/helm-charts/contents/helmfiles/{module}?ref={branch}"
        resp = requests.get(version_url)
        if resp.status_code != 200:
            print(f"⚠️ Failed to fetch versions for '{module}': {resp.text}")
            continue

        versions = [item["name"] for item in resp.json() if item["name"].endswith(".yaml")]
        if not versions:
            print(f"⚠️ No helmfile versions found for module '{module}', skipping.")
            continue

        # --- Auto-pick latest for backbone ---
        if module.lower() == "backbone":
            valid_versions = []
            for v in versions:
                try:
                    ver = version.parse(v.replace(".yaml", ""))
                    valid_versions.append((ver, v))
                except Exception:
                    pass
            latest = (
                sorted(valid_versions, key=lambda x: x[0], reverse=True)[0][1]
                if valid_versions
                else versions[0]
            )
            print(f"✅ Automatically selected latest backbone version: {latest}")
            selected_versions.append(latest)
            continue

        # --- Let user select version for other modules ---
        if len(versions) == 1:
            version_choice = versions[0]
            print(f"✅ Only one version found ({version_choice}), auto-selecting it.")
        else:
            version_choice = inquirer.select(
                message=f"Select helmfile version for module '{module}':",
                choices=versions,
            ).execute()

        selected_versions.append(version_choice)

    print("\n✅ Final module and version selections:")
    for m, v in zip(selected_modules, selected_versions):
        print(f"   - {m}: {v}")

    return selected_modules, selected_versions

def create_terraform_commands(cloud, work_dir, session, region, cluster_name):
    def execute(directory, description):
        """Runs terraform init and apply inside the given directory."""
        cmds = [
            ["terraform", "init"],
            ["terraform", "plan"],
            ["terraform", "apply", "-auto-approve"]
        ]
        for cmd in cmds:
            print(f"🔧 Running: {' '.join(cmd)} in {directory}")
            try:
                subprocess.run(cmd, cwd=directory, check=True)
            except subprocess.CalledProcessError as e:
                 # Show a clean error message to user
                print(f"\n❌ Terraform command failed in {description}: {' '.join(cmd)}")
                if e.stdout:
                    print(f"Output:\n{e.stdout}")
                if e.stderr:
                    print(f"Error:\n{e.stderr}")
                print("\nPlease check the above error and fix it before retrying.")
                sys.exit(1)
    if cloud == "aws":
        # Run Terraform in remote-state and main directories
        execute(work_dir / "remote-state", "Terraform remote-state")
        bucket_name = fetch_s3_bucket_from_api(cluster_name, session)
        update_main_backend_with_bucket(work_dir, bucket_name, region)
        execute(work_dir, "Terraform main directory")

def upgrade_terraform_commands(cloud, work_dir, session, region, cluster_name):
    def execute(directory, description):
        """Runs terraform init and apply inside the given directory."""
        cmds = [
            ["terraform", "init"],
            ["terraform", "plan"],
            ["terraform", "apply"]
        ]
        for cmd in cmds:
            print(f"🔧 Running: {' '.join(cmd)} in {directory}")
            try:
                subprocess.run(cmd, cwd=directory, check=True)
            except subprocess.CalledProcessError as e:
                 # Show a clean error message to user
                print(f"\n❌ Terraform command failed in {description}: {' '.join(cmd)}")
                if e.stdout:
                    print(f"Output:\n{e.stdout}")
                if e.stderr:
                    print(f"Error:\n{e.stderr}")
                print("\nPlease check the above error and fix it before retrying.")
                sys.exit(1)
    if cloud == "aws":
        # Run Terraform in  main directory
        bucket_name = fetch_s3_bucket_from_api(cluster_name, session)
        update_main_backend_with_bucket(work_dir, bucket_name, region)
        execute(work_dir, "Terraform main directory")

def destroy_terraform_commands(cloud, work_dir, session, region, cluster_name):
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
            sys.exit(1)
            return False
        except json.JSONDecodeError as e:
            print(f"❌ JSON parsing error while checking S3 bucket: {e}")
            sys.exit(1)
            return False
        
    def delete_s3_and_dynamodb(name, session):
        print(f"🧹 Deleting resources with name: {name}")

        s3 = session.client('s3')
        dynamodb = session.client('dynamodb')

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
            sys.exit(1)

        # Step 2: Delete the S3 bucket itself
        try:
            s3.delete_bucket(Bucket=name)
            print(f"✅ Deleted S3 bucket: {name}")
        except ClientError as e:
            print(f"⚠️ Could not delete bucket: {e.response['Error']['Message']}")
            sys.exit(1)

        # Step 3: Delete DynamoDB table
        try:
            print(f"🔸 Deleting DynamoDB table: {name}")
            dynamodb.delete_table(TableName=name)
            waiter = dynamodb.get_waiter('table_not_exists')
            waiter.wait(TableName=name)
            print(f"✅ Deleted DynamoDB table: {name}")
        except ClientError as e:
            print(f"⚠️ Skipped DynamoDB deletion: {e.response['Error']['Message']}")
            sys.exit(1)

    def execute(directory, description):
        """Runs terraform init and apply inside the given directory."""
        cmds = [
            ["terraform", "init"],
            ["terraform", "destroy"]
        ]
        for cmd in cmds:
            print(f"🔧 Running: {' '.join(cmd)} in {directory}")
            try:
                subprocess.run(cmd, cwd=directory, check=True)
            except subprocess.CalledProcessError as e:
                 # Show a clean error message to user
                print(f"\n❌ Terraform command failed in {description}: {' '.join(cmd)}")
                if e.stdout:
                    print(f"Output:\n{e.stdout}")
                if e.stderr:
                    print(f"Error:\n{e.stderr}")
                print("\nPlease check the above error and fix it before retrying.")
                sys.exit(1)
    if cloud == "aws":
        # Run Terraform in  main directory
        bucket_name = fetch_s3_bucket_from_api(cluster_name, session)
        bucket_empty = is_s3_bucket_empty(bucket_name)
        if bucket_empty:
            print("📦 Bucket is empty. Proceeding to destroy S3 bucket and Dynamodb table.")
            delete_s3_and_dynamodb(bucket_name, session)
        else:
            print("📦 Bucket is NOT empty. Proceeding with 2-step destroy.")
            update_main_backend_with_bucket(work_dir, bucket_name, region)
            execute(work_dir, "Terraform main directory")
            delete_s3_and_dynamodb(bucket_name, session)

def update_env_files(env_file, env_secrets, terraform_dir, domain_name):
    """
    Fetch terraform outputs, DB password from Secrets Manager, and replace placeholders in env files.
    """

    print("\n🔍 Fetching Terraform outputs...")
    try:
        result = subprocess.run(
            ["terraform", "output", "-json"],
            cwd=terraform_dir,
            capture_output=True,
            text=True,
            check=True
        )
        tf_outputs = json.loads(result.stdout)
        print("✅ Terraform outputs fetched successfully.")
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to get terraform outputs:\n{e.stderr}")
        sys.exit(1)

    # --- Extract DB password from AWS Secrets Manager ---
    # print(f"\n🔍 Fetching DB password from secret: {db_secret_name} ...")
    # try:
    #     secret_cmd = ["aws", "secretsmanager", "get-secret-value", "--secret-id", db_secret_name, "--query", "SecretString", "--output", "text"]
    #     secret_result = subprocess.run(secret_cmd, capture_output=True, text=True, check=True)
    #     secret_data = json.loads(secret_result.stdout)
    #     db_password = secret_data.get("password") or secret_data.get("DB_PASSWORD")
    #     if not db_password:
    #         print("⚠️ DB password key not found in secret JSON. Please check the secret structure.")
    #         sys.exit(1)
    #     print("✅ Retrieved DB password from Secrets Manager.")
    # except subprocess.CalledProcessError as e:
    #     print(f"❌ Failed to retrieve DB password:\n{e.stderr}")
    #     sys.exit(1)

    # --- Prepare replacements ---
    replacements = {
        "<db_host_name>": tf_outputs.get("db_host_name", {}).get("value", ""),
        "<db_name>": tf_outputs.get("db_name", {}).get("value", ""),
        "<db_username>": tf_outputs.get("db_username", {}).get("value", ""),
        "<domain_name>": domain_name,
    }

    # --- Replace placeholders in both files ---
    def replace_in_file(file_path):
        print(f"✏️ Updating {file_path}...")
        try:
            with open(file_path, "r") as f:
                content = f.read()

            for key, value in replacements.items():
                if key in content:
                    content = content.replace(key, str(value))

            with open(file_path, "w") as f:
                f.write(content)
            print(f"✅ Updated {file_path}")
        except FileNotFoundError:
            print(f"⚠️ File not found: {file_path}")
        except Exception as e:
            print(f"❌ Error updating {file_path}: {e}")
            sys.exit(1)

    replace_in_file(env_file)
    replace_in_file(env_secrets)

    print("\n🎉 Environment files updated successfully!")

def run_deployment(work_dir, extra_args=None):
    """
    Runs the Helmfile deployment script after env file updates.
    Passes env and secrets files as arguments.
    """

    print("\n🚀 Starting Helmfile deployment...")
    deployment_script = work_dir/"helmfile_deploy.py" 

    if not os.path.exists(deployment_script):
        print(f"❌ Deployment script not found at: {deployment_script}")
        sys.exit(1)

    # Construct the command
    cmd = [
        "python3",
        "helmfile_deploy.py",
        "--env-file", "env-templates/env.yaml",
        "--secrets-file", "env-templates/env-secrets.yaml",
        "--branch", "automation"
    ]
    if extra_args:
        cmd.extend(extra_args)

    try:
        subprocess.run(cmd, cwd=work_dir, check=True)
        print("✅ Deployment completed successfully.")
        # print("🧾 Deployment logs:\n", result.stdout)
    except subprocess.CalledProcessError as e:
        print("❌ Deployment script failed!")
        print("🧾 STDERR:\n", e.stderr)
        print("🧾 STDOUT:\n", e.stdout)
        sys.exit(1)

def configure_kubeconfig(cluster_name, region, profile=None):
    """
    Fetches and updates kubeconfig for the created EKS cluster.
    Merges it into ~/.kube/config and verifies the context.
    """
    print(f"\n⚙️ Generating kubeconfig for EKS cluster: {cluster_name} (region: {region})")

    # --- Wait for the cluster to become ACTIVE ---
    wait_cmd = ["aws", "eks", "wait", "cluster-active", "--name", cluster_name, "--region", region]
    if profile:
        wait_cmd += ["--profile", profile]

    print("⏳ Waiting for EKS cluster to become active...")
    try:
        subprocess.run(wait_cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        print("✅ Cluster is active.")
    except subprocess.CalledProcessError:
        print(f"⚠️ Timeout or error waiting for cluster '{cluster_name}' to become active. Proceeding anyway...")

    # --- Update kubeconfig ---
    update_cmd = [
        "aws", "eks", "update-kubeconfig",
        "--name", cluster_name,
        "--region", region,
        "--alias", cluster_name
    ]
    if profile:
        update_cmd += ["--profile", profile]

    try:
        subprocess.run(update_cmd, check=True)
        print(f"✅ Kubeconfig updated successfully for cluster '{cluster_name}'")
    except subprocess.CalledProcessError as e:
        print(f"❌ Failed to update kubeconfig for {cluster_name}.")
        if e.stderr:
            print(f"Error:\n{e.stderr.decode() if isinstance(e.stderr, bytes) else e.stderr}")
        sys.exit(1)

    # --- Verify kubeconfig and context ---
    try:
        print("\n🔍 Verifying Kubernetes connection...")
        subprocess.run(["kubectl", "config", "use-context", cluster_name], check=True)
        subprocess.run(["kubectl", "get", "nodes"], check=True)
        print("✅ Verified kubeconfig context and cluster access.")
    except subprocess.CalledProcessError:
        print("⚠️ Unable to verify cluster context. Please check manually with:")
        print(f"   kubectl config get-contexts && kubectl get nodes")

def check_and_delete_loadbalancers(cluster_name):
    try:
        print("\n🔍 Verifying Kubernetes connection...")
        subprocess.run(["kubectl", "config", "use-context", cluster_name], check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run(["kubectl", "get", "nodes"], check=True)
        print("✅ Verified kubeconfig context and cluster access.")

        # Get all LoadBalancer-type services across namespaces
        print("\n🔍 Checking for LoadBalancer services...")
        result = subprocess.run(
            ["kubectl", "get", "svc", "--all-namespaces", "-o", "json"],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True
        )
        services = json.loads(result.stdout)
        lb_services = [
            f"{svc['metadata']['namespace']}/{svc['metadata']['name']}"
            for svc in services["items"]
            if svc["spec"].get("type") == "LoadBalancer"
        ]

        if not lb_services:
            print("✅ No LoadBalancer services found. Continuing with infra destroy...")
            return True

        print(f"⚠️ Found {len(lb_services)} LoadBalancer service(s):")
        for s in lb_services:
            print(f"   - {s}")

        # Try deleting them
        for s in lb_services:
            ns, name = s.split("/")
            print(f"🧹 Deleting LoadBalancer: {s}")
            try:
                subprocess.run(
                    ["kubectl", "delete", "svc", name, "-n", ns],
                    check=True
                )
                print(f"✅ Deleted {s}")
            except subprocess.CalledProcessError:
                print(f"❌ Failed to delete {s}. Please delete it manually before destroying infra.")
                return False

        print("✅ All LoadBalancers deleted successfully.")
        return True

    except subprocess.CalledProcessError:
        print("⚠️ Unable to verify cluster context. Please check manually with:")
        print(f"   kubectl config get-contexts && kubectl get nodes")
        return False

def main():
    parser = argparse.ArgumentParser(description="Deploy DIGIT Platform")
    parser.add_argument('--create', action='store_true', help='Create infrastructure and Deploy the Application')
    parser.add_argument('--upgrade', action='store_true', help='Upgrade infrastructure and Deploy the Application ')
    parser.add_argument('--destroy', action='store_true', help='Destroy infrastructure')
    parser.add_argument("--var", action="append", help="Pass additional Terraform variables (e.g., --var key=value). Can be used multiple times.")
    parser.add_argument('--deploy', action='store_true', help='Deploy the Application')
    args = parser.parse_args()
    cloud_choice = inquirer.select(
        message="Choose your cloud provider:",
        choices=[
            {"name": "AWS", "value": "aws"},
            {"name": "Azure", "value": "azure"},
            {"name": "GCP", "value": "gcp"},
        ],
    ).execute()
    cluster_name = input("Enter the Cluster Name: ")
    if not cluster_name:
            raise ValueError("[Step: Input] Cluster name cannot be empty.")
    try:
        if args.create:
            domain_name = input("Enter the Domain Name: ")
            if not domain_name:
                raise ValueError("[Step: Input] Domain name cannot be empty.")
            if cloud_choice == "aws":
                run_dir = create_run_directory(cluster_name)
                zip_ref = download_github_zip()
                extract_cloud_modules(zip_ref, run_dir, cloud_choice)
                print(f"🎉 All relevant directories fetched under: {run_dir}")
                os.environ.pop('AWS_PROFILE', None)
                ensure_aws_dependencies(run_dir)
                config = get_aws_inputs_and_validate()
                modules, versions = get_deployment_choices(branch="automation")
                work_dir = run_dir/f"{REPO_NAME}-{BRANCH}/infra-as-code/terraform/sample-{cloud_choice}"
                extra_vars = args.var or [] 
                vars_dict = {
                    "cluster_name": cluster_name,
                    "region": config['region'],
                }
                generate_tfvars_for_cloud(cloud_choice, work_dir, vars_dict, extra_vars)
                download_deployment_files(
                    owner="egovernments",
                    repo="helm-charts",
                    branch="automation",
                    paths=["env-templates", "helmfile_deploy.py"],
                    dest_dir=run_dir/f"{REPO_NAME}-{BRANCH}"
                )
                print("\n✅ Deployment files ready at:", run_dir/f"{REPO_NAME}-{BRANCH}")
                check_aws_existing_resources(config['session'], cluster_name, config['region'])
                actions = load_actions_from_yaml(work_dir, 'permissions.yaml')
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
                create_terraform_commands(cloud_choice, work_dir,config['session'], config['region'], cluster_name)
                configure_kubeconfig(cluster_name, config['region'], config.get('profile'))
                update_env_files(run_dir/f"{REPO_NAME}-{BRANCH}/env-templates/env.yaml", run_dir/f"{REPO_NAME}-{BRANCH}/env-templates/env-secrets.yaml", work_dir, domain_name)
                run_deployment(run_dir/f"{REPO_NAME}-{BRANCH}", extra_args=["--modules", *modules,"--versions", *versions,])
            elif cloud_choice == "azure":
                run_dir = create_run_directory(cluster_name)
                zip_ref = download_github_zip()
                extract_cloud_modules(zip_ref, run_dir, cloud_choice)
                print(f"🎉 All relevant directories fetched under: {run_dir}")
                ensure_azure_dependencies(run_dir)
                print("🚀 Azure Credential & Permission Validator")
                selected_profile = select_or_create_profile()
                region = input("Enter the Region Name: ")
                validate_azure_location(region)
                set_azure_env(selected_profile)
                object_id = get_current_sp_object_id(selected_profile)
                check_permissions(object_id)
            elif cloud_choice == "gcp":
                run_dir = create_run_directory(cluster_name)
                zip_ref = download_github_zip()
                extract_cloud_modules(zip_ref, run_dir, cloud_choice)
                print(f"🎉 All relevant directories fetched under: {run_dir}")
                ensure_gcp_dependencies(run_dir)
                # ✅ Ensure default login is set
                try:
                    subprocess.run(
                        ["gcloud", "auth", "application-default", "print-access-token"],
                        check=True,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.DEVNULL
                    )
                    print("✅ gcloud already authenticated with application-default login.")
                except subprocess.CalledProcessError:
                    print("⚠️ gcloud not authenticated. Running application-default login...")
                    subprocess.run(["gcloud", "auth", "application-default", "login"], check=True)
            else:
                print("Only AWS,Azure and GCP are currently supported. Others are not supported!")
        elif args.upgrade:
            domain_name = input("Enter the Domain Name: ")
            if not domain_name:
                raise ValueError("[Step: Input] Domain name cannot be empty.")
            if cloud_choice == "aws":
                run_dir = create_run_directory(cluster_name)
                zip_ref = download_github_zip()
                extract_cloud_modules(zip_ref, run_dir, cloud_choice)
                print(f"🎉 All relevant directories fetched under: {run_dir}")
                os.environ.pop('AWS_PROFILE', None)
                ensure_aws_dependencies(run_dir)
                config = get_aws_inputs_and_validate()
                deployment = input("Do you want to proceed with the deployment after creating the infra? (y/n): ").strip().lower()
                if (deployment in ['y', 'yes']) or not deployment:
                    modules, versions = get_deployment_choices(branch="automation")
                work_dir = run_dir/f"{REPO_NAME}-{BRANCH}/infra-as-code/terraform/sample-{cloud_choice}"
                extra_vars = args.var or [] 
                vars_dict = {
                    "cluster_name": cluster_name,
                    "region": config['region'],
                }
                generate_tfvars_for_cloud(cloud_choice, work_dir, vars_dict, extra_vars)
                if (deployment in ['y', 'yes']) or not deployment:
                    download_deployment_files(
                        owner="egovernments",
                        repo="helm-charts",
                        branch="automation",
                        paths=["env-templates", "helmfile_deploy.py"],
                        dest_dir=run_dir/f"{REPO_NAME}-{BRANCH}"
                    )
                    print("\n✅ Deployment files ready at:", run_dir/f"{REPO_NAME}-{BRANCH}")
                s3_state_bucket = fetch_s3_bucket_from_api(cluster_name, config['session'])
                check_aws_existing_resources(config['session'], cluster_name, config['region'], s3_state_bucket)
                actions = load_actions_from_yaml(work_dir, 'permissions.yaml')
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
                upgrade_terraform_commands(cloud_choice, work_dir,config['session'], config['region'], cluster_name)
                configure_kubeconfig(cluster_name, config['region'], config.get('profile'))
                if (deployment in ['y', 'yes']) or not deployment:
                    update_env_files(run_dir/f"{REPO_NAME}-{BRANCH}/env-templates/env.yaml", run_dir/f"{REPO_NAME}-{BRANCH}/env-templates/env-secrets.yaml", work_dir, domain_name)
                    run_deployment(run_dir/f"{REPO_NAME}-{BRANCH}", extra_args=["--modules", *modules,"--versions", *versions,])
            else:
                print("Only AWS is currently supported. Others are not supported!")
        elif args.destroy:
            if cloud_choice == "aws":
                run_dir = create_run_directory(cluster_name)
                zip_ref = download_github_zip()
                extract_cloud_modules(zip_ref, run_dir, cloud_choice)
                print(f"🎉 All relevant directories fetched under: {run_dir}")
                os.environ.pop('AWS_PROFILE', None)
                ensure_aws_dependencies(run_dir)
                config = get_aws_inputs_and_validate()
                work_dir = run_dir/f"{REPO_NAME}-{BRANCH}/infra-as-code/terraform/sample-{cloud_choice}"
                extra_vars = args.var or [] 
                vars_dict = {
                    "cluster_name": cluster_name,
                    "region": config['region'],
                }
                generate_tfvars_for_cloud(cloud_choice, work_dir, vars_dict, extra_vars)
                actions = load_actions_from_yaml(work_dir, 'permissions.yaml')
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
                success = check_and_delete_loadbalancers(cluster_name)
                if not success:
                    print("🚫 Exiting gracefully due to LoadBalancer cleanup failure.")
                    sys.exit(0)
                destroy_terraform_commands(cloud_choice, work_dir,config['session'], config['region'], cluster_name)
            else:
                print("Only AWS is currently supported. Others are not supported!")
        elif args.deploy:
            domain_name = input("Enter the Domain Name: ")
            if not domain_name:
                raise ValueError("[Step: Input] Domain name cannot be empty.")
            run_dir = create_run_directory(cluster_name)
            work_dir = run_dir/f"{REPO_NAME}-{BRANCH}"
            download_deployment_files(
                owner="egovernments",
                repo="helm-charts",
                branch="automation",
                paths=["env-templates", "helmfile_deploy.py"],
                dest_dir=run_dir/f"{REPO_NAME}-{BRANCH}"
            )
            print("\n✅ Deployment files ready at:", run_dir/f"{REPO_NAME}-{BRANCH}")
            update_env_files(run_dir/f"{REPO_NAME}-{BRANCH}/env-templates/env.yaml", run_dir/f"{REPO_NAME}-{BRANCH}/env-templates/env-secrets.yaml", work_dir, domain_name)
            run_deployment(run_dir/f"{REPO_NAME}-{BRANCH}")
        else:
            print("❗ Please specify --create --upgrade or --destroy")
    except Exception as e:
        step = "Unknown Step"
        if "[Step:" in str(e):
            print(f"\n{e}\n")
        else:
            print(f"\n❌ [General Error] {e}\n")

if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit("\n❌ Interrupted by user")
    except Exception as e:
        sys.exit(f"❌ Error: {e}")
