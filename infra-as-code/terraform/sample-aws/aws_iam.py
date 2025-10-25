import subprocess
import sys
import os
import configparser
import yaml
from pathlib import Path
import threading
import itertools
import time
import boto3
import botocore
from botocore.exceptions import ProfileNotFound

VALID_AWS_REGIONS = [
    "us-east-1", "us-east-2", "us-west-1", "us-west-2",
    "ap-south-1", "ap-northeast-1", "ap-northeast-2",
    "ap-southeast-1", "ap-southeast-2",
    "ca-central-1", "eu-central-1", "eu-west-1",
    "eu-west-2", "eu-west-3", "sa-east-1",
    "me-south-1", "af-south-1"
]

def is_valid_region(region):
    return region in VALID_AWS_REGIONS

def get_aws_inputs_and_validate():
    print("\n--- AWS Configuration ---")

    existing_profiles = check_existing_profiles()
    profile_name = choose_or_create_profile(existing_profiles)

    aws_config_dir = os.path.expanduser("~/.aws")
    config_path = os.path.join(aws_config_dir, "config")
    config = configparser.ConfigParser()
    config.read(config_path)

    profile_key = f"profile {profile_name}" if profile_name != "default" else "default"

    # --- Function to prompt user for region ---
    def prompt_for_region(current_region=None):
        while True:
            if current_region:
                print(f"\nProfile '{profile_name}' is currently configured with region: '{current_region}'")
                user_region = input("Press Enter to use this region, or type a new region to override: ").strip()
                region_to_use = user_region if user_region else current_region
            else:
                region_to_use = input(f"Enter AWS Region for profile '{profile_name}' (e.g., us-east-1): ").strip()

            if is_valid_region(region_to_use):
                return region_to_use
            else:
                print(f"❌ '{region_to_use}' is not a valid AWS region. Please try again.\n")

    # --- Determine region ---
    if config.has_section(profile_key) and config.has_option(profile_key, "region"):
        region = prompt_for_region(config.get(profile_key, "region").strip())
    else:
        region = prompt_for_region()

     # --- New profile workflow ---
    if profile_name not in existing_profiles:
        while True:
            print(f"\nConfiguring new AWS profile '{profile_name}' with region '{region}'")
            access_key = input("Enter AWS Access Key ID: ").strip()
            secret_key = input("Enter AWS Secret Access Key: ").strip()

            status = validate_aws_credentials(access_key, secret_key, region)
            
            if status == "valid":
                configure_aws_profile(profile_name, access_key, secret_key, region)
                if not config.has_section(profile_key):
                    config.add_section(profile_key)
                config.set(profile_key, "region", region)
                with open(config_path, "w", encoding="utf-8") as f:
                    config.write(f)
                session = boto3.Session(profile_name=profile_name, region_name=region)
                print(f"✅ AWS profile '{profile_name}' configured successfully.")
                return {
                    "access_key": access_key,
                    "secret_key": secret_key,
                    "region": region,
                    "session": session,
                    "profile": profile_name
                }

            elif status == "invalid_region":
                print("❌ The region is invalid or disabled. Please choose a different region.\n")
                region = prompt_for_region()
                continue  # retry with new region + credentials

            elif status == "invalid_credentials":
                print("❌ AWS credentials are invalid. Please try again.\n")
                continue  # retry credentials only

            else:
                print("❌ Unexpected error. Please check your inputs.\n")
                continue

    # --- For existing profiles, validate credentials and region ---
    while True:
        try:
            session = boto3.Session(profile_name=profile_name, region_name=region)
            sts = session.client("sts")
            identity = sts.get_caller_identity()

            print(f"✅ Using profile '{profile_name}' with region '{region}'.")
            print(f"Account: {identity['Account']}, ARN: {identity['Arn']}")

            # Update config file with region
            if not config.has_section(profile_key):
                config.add_section(profile_key)
            config.set(profile_key, "region", region)
            with open(config_path, "w", encoding="utf-8") as config_file:
                config.write(config_file)

            return {
                "access_key": "From profile",
                "secret_key": "From profile",
                "region": region,
                "session": session,
                "profile": profile_name
            }

        except Exception as e:
            error_message = str(e)

            # Region-related errors
            if any(keyword in error_message for keyword in [
                "InvalidClientTokenId",
                "AuthFailure",
                "InvalidEndpointURL",
                "could not be found",
                "could not connect to the endpoint",
                "is not enabled in this region"
            ]):
                print(f"\n❌ The region '{region}' appears disabled or unsupported for your account.")
                print("Please choose another valid region.\n")
                region = prompt_for_region()  # re-prompt for region
                continue  # retry STS check with new region

            # Credentials issue → prompt for reconfiguration
            print(f"⚠️ Failed to use profile '{profile_name}': {error_message}")
            print("Please provide AWS credentials to reconfigure this profile.\n")

            access_key = input("Enter AWS Access Key ID: ").strip()
            secret_key = input("Enter AWS Secret Access Key: ").strip()
            status = validate_aws_credentials(access_key, secret_key, region)

            if status == "valid":
                configure_aws_profile(profile_name, access_key, secret_key, region)
                # Update config file with region
                if not config.has_section(profile_key):
                    config.add_section(profile_key)
                config.set(profile_key, "region", region)
                with open(config_path, "w", encoding="utf-8") as config_file:
                    config.write(config_file)
                continue  # retry STS validation
            else:
                print("⚠️ AWS credentials are invalid. Please try again.\n")


def check_existing_profiles():
    profiles = []
    try:
        result = subprocess.run(["aws", "configure", "list-profiles"], capture_output=True, text=True)
        profiles = result.stdout.strip().splitlines()
    except Exception as e:
        print("Could not list AWS profiles:", e)
    return profiles

def choose_or_create_profile(existing_profiles):
    print("\n--- AWS Profile Selection ---")

    if "default" in existing_profiles:
        use_default = input("Found 'default' AWS profile. Do you want to use it? (y/n): ").strip().lower()
        if use_default in ['y', 'yes']:
            print("✅ Using default AWS profile.")
            return "default"
        if not use_default:
            print("✅ Using default AWS profile.")
            return "default"

    if existing_profiles:
        print("Available profiles:")
        for profile in existing_profiles:
            print(f"- {profile}")

        while True:
            use_existing = input("\nDo you want to use one of the existing profiles? (y/n): ").strip().lower()
            if use_existing in ['y', 'yes']:
                while True:
                    selected = input("Enter the name of the existing profile to use: ").strip()
                    if selected in existing_profiles:
                        print(f"✅ Using AWS profile '{selected}'.")
                        return selected
                    else:
                        print("❌ That profile name does not exist. Try again.")
            elif use_existing in ['n', 'no']:
                break
            else:
                print("❌ Invalid input. Please enter 'y' or 'n'.")

    # Fallthrough to create new profile
    new_profile = input("Enter name for the new AWS profile (press Enter for 'default'): ").strip()
    if not new_profile:
        new_profile = "default"
        print("ℹ️  No profile name entered. Using 'default' as the profile name.")
    else:
        print(f"✅ Creating new profile '{new_profile}'.")
    return new_profile


def validate_aws_credentials(access_key, secret_key, region):
    import boto3
    from botocore.exceptions import NoCredentialsError, PartialCredentialsError, ClientError, EndpointConnectionError

    try:
        session = boto3.Session(
            aws_access_key_id=access_key,
            aws_secret_access_key=secret_key,
            region_name=region
        )
        sts = session.client("sts")
        identity = sts.get_caller_identity()
        print("✅ AWS credentials are valid.")
        print(f"Account: {identity['Account']}, ARN: {identity['Arn']}")
        return "valid"  # return string status

    except NoCredentialsError:
        print(f"❌ No credentials provided or credentials are not properly configured.")
        return "invalid_credentials"

    except EndpointConnectionError:
        print(f"❌ Cannot connect to endpoint in region '{region}'. This region may be disabled or unsupported.")
        return "invalid_region"

    except ClientError as e:
        error_code = e.response['Error']['Code']

        # Region-related errors
        if error_code in ["AuthFailure", "InvalidEndpoint", "InvalidEndpointURL"]:
            print(f"❌ The region '{region}' appears disabled or unsupported for your account.")
            return "invalid_region"

        # Credentials-related errors
        if error_code == "InvalidClientTokenId":
            print("❌ The provided AWS Access Key or Secret Key is invalid. Please try again.")
            return "invalid_credentials"

        print(f"❌ AWS Client error: {e.response['Error']['Message']}")
        return "error"

    except Exception as e:
        print(f"❌ Unexpected error: {str(e)}")
        return "error"



def configure_aws_profile(profile_name, access_key, secret_key, region):
    aws_config_dir = os.path.expanduser("~/.aws")
    os.makedirs(aws_config_dir, exist_ok=True)

    credentials_path = os.path.join(aws_config_dir, "credentials")
    config_path = os.path.join(aws_config_dir, "config")

    # Write credentials
    with open(credentials_path, "a", encoding="utf-8", newline='') as cred_file:
        cred_file.write(f"\n[{profile_name}]\naws_access_key_id={access_key}\naws_secret_access_key={secret_key}\n")

    # Write config
    with open(config_path, "a", encoding="utf-8", newline='') as config_file:
        config_file.write(f"\n[profile {profile_name}]\nregion={region}\n")

    print(f"✅ AWS CLI profile '{profile_name}' configured.")

class Spinner:
    def __init__(self, message="Verifying roles..."):
        self.spinner = itertools.cycle(['|', '/', '-', '\\'])
        self.stop_running = threading.Event()
        self.message = message
        self.thread = threading.Thread(target=self._spin)

    def _spin(self):
        while not self.stop_running.is_set():
            sys.stdout.write(f"\r{self.message} {next(self.spinner)}")
            sys.stdout.flush()
            time.sleep(0.1)
        sys.stdout.write('\r' + ' ' * (len(self.message) + 2) + '\r')

    def start(self):
        self.thread.start()

    def stop(self):
        self.stop_running.set()
        self.thread.join()

def get_identity_and_context(session):
    sts = session.client("sts")
    identity = sts.get_caller_identity()
    return {
        "account_id": identity["Account"],
        "caller_arn": identity["Arn"],
        "region": session.region_name or "ap-south-1"  # fallback
    }

def setup_session(profile_name, region):
    session = boto3.Session(profile_name=profile_name, region_name=region)
    creds = session.get_credentials().get_frozen_credentials()

    os.environ["AWS_ACCESS_KEY_ID"] = creds.access_key
    os.environ["AWS_SECRET_ACCESS_KEY"] = creds.secret_key
    if creds.token:
        os.environ["AWS_SESSION_TOKEN"] = creds.token

    os.environ["AWS_REGION"] = region

    return session

def load_actions_from_yaml(working_dir, yaml_file):
    file = Path(working_dir)/yaml_file
    with open(file, 'r') as f:
        data = yaml.safe_load(f)
    return data.get('actions', [])

def simulate_permissions(session, actions, cluster_name):
    context = get_identity_and_context(session)
    iam = session.client("iam")
    results = {}
    KUBERNETES_CLUSTER_NAME = cluster_name
    for action in actions:
        # resource_arn = build_resource_arn(action, context["account_id"], context["region"], cluster_name)
        # if not isinstance(resource_arn, list):
        resource_arn = ["*"]
        try:
            resp = iam.simulate_principal_policy(
                PolicySourceArn=context["caller_arn"],
                ActionNames=[action],
                ResourceArns=resource_arn
            )
            decision = resp["EvaluationResults"][0]["EvalDecision"]
        except Exception as e:
            decision = f"error: {str(e)}"

        results[action] = {
            "decision": decision.lower(),
            "resource": ", ".join(resource_arn)
        }

    return results

def print_results(results):
    denied = []
    errors = []

    for action, res in results.items():
        # if res["decision"] == "allowed":
        #     print(f"✅ {action} on {res['resource']} is ALLOWED")
        if res["decision"] == "explicitdeny" or res["decision"] == "implicitdeny":
            # print(f"❌ {action} on {res['resource']} is DENIED")
            denied.append((action, res["resource"]))
        elif res["decision"].startswith("error"):
            errors.append((action, res["decision"]))
            print(f"⚠️  {action} - ERROR: {res['decision']}")

    if not denied and not errors:
        print("✅ All the required permissions are present to create infra.")
    else:
        print("❌ Missing or failed permissions: Refer to https://core.digit.org/ for more info.\n")

