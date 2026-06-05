# DIGIT 3 — Quick Setup on AWS (GitHub Actions)

> **Scope:** Dev and test environments only. Not for production.
>
> **Region:** `ap-south-1` is hardcoded in the Terraform scripts. Support for configurable regions is planned.
>
> **Secrets:** Sensitive values in `egov-demo-secrets.yaml` should be encrypted with SOPS before committing to a repository. Use a **private repository** until SOPS encryption is in place.

---

## What Changed from DIGIT 2.9 LTS

| Area | DIGIT 2.9 LTS | DIGIT 3 |
|---|---|---|
| EC2 node SSH key | Required (`ssh_key_name` + `public_ssh_key` in `input.yaml`) | **Removed** — nodes use AWS SSM for access |
| git-sync SSH key | Required — MDMS and config repos pulled via SSH | **Removed** — DIGIT 3 services do not use git-sync at all |
| MDMS storage | Git repo cloned at pod startup via git-sync | PostgreSQL database (`mdms-v2` service) |
| Database | RDS (managed) | In-cluster PostgreSQL pod |
| `input.yaml` fields | 7 fields | 3 fields |
| Secrets file path | `deploy-as-code/charts/environments/env-secrets.yaml` | `deploy-as-code/helm/environments/egov-demo-secrets.yaml` |
| Authentication | Zuul gateway | Keycloak |
| Secret encryption | Not enforced | SOPS + KMS (KMS key created by Terraform) |
| Kubernetes version | Older | 1.33 |
| Worker node AMI | Bottlerocket | Amazon Linux 2023 (AL2023) |
| GitHub Actions branch | `release-githubactions` | `digit3-infra` |

---

## Pre-requisites

- AWS account with administrative privileges
- GitHub account
- Git installed locally

---

## Step 1 — Create IAM User and Generate Access Keys

> Skip this step if you already have an `ACCESS_KEY` and `SECRET_KEY`.

1. Log in to your AWS console.
2. Navigate to **IAM → Users → Create user**.
3. Attach the **AdministratorAccess** policy.
4. Go to **Security credentials → Create access key** and copy the values.

Your keys will look like:

```
AWS_ACCESS_KEY_ID     = AKIA**************FQ
AWS_SECRET_ACCESS_KEY = tqM**********************+lfTt
AWS_REGION            = ap-south-1
```

---

## Step 2 — Configure the GitHub Repository

### 2a. Fork the repository

Fork `DIGIT-DevOps` into your GitHub account. When prompted, **uncheck "Copy the master branch only"** so all branches are available.

### 2b. Enable GitHub Actions

After forking, open the **Actions** tab and click **"I understand my workflows, go ahead and enable them"**.

### 2c. Add repository secrets

Navigate to **Settings → Security → Secrets and variables → Actions → New repository secret** and add each of the following:

| Secret Name | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | Your IAM access key |
| `AWS_SECRET_ACCESS_KEY` | Your IAM secret key |
| `AWS_DEFAULT_REGION` | `ap-south-1` (or your target region) |
| `AWS_REGION` | `ap-south-1` (or your target region) |

### 2d. Clone the repository and switch branches

```bash
git clone https://github.com/<your-github-username>/DIGIT-DevOps.git
cd DIGIT-DevOps
git checkout digit3-infra
```

---

## Step 3 — Configure Infrastructure Parameters

Open [infra-as-code/terraform/sample-aws/input.yaml](infra-as-code/terraform/sample-aws/input.yaml) and fill in the three required values:

```yaml
# Lowercase alphanumeric characters and hyphens only. Example: "digit-demo"
cluster_name: "<your-cluster-name>"

# The domain URL for the DIGIT UI. Example: "demo.digit.org"
domain_name: "<your-domain-name>"

# Name for the S3 bucket that stores Terraform state. Must be globally unique.
terraform_state_bucket_name: "<your-tf-state-bucket-name>"
```

> **Compared to DIGIT 2.9 LTS:** The fields `ssh_key_name`, `public_ssh_key`, `db_name`, and `db_username` are no longer present. RDS has been removed in favour of an in-cluster PostgreSQL pod.

### Optional infrastructure tuning (variables.tf)

These defaults in [infra-as-code/terraform/sample-aws/variables.tf](infra-as-code/terraform/sample-aws/variables.tf) can be changed if needed:

| Variable | Default | Description |
|---|---|---|
| `architecture` | `x86_64` | Worker node arch. Set to `arm64` for Graviton |
| `instance_types` | `[]` (auto from arch) | Override instance type, e.g. `["m5a.2xlarge"]` |
| `min_worker_nodes` | `1` | Minimum EKS nodes |
| `desired_worker_nodes` | `3` | Desired EKS nodes |
| `max_worker_nodes` | `5` | Maximum EKS nodes |
| `enable_karpenter` | `false` | Enable Karpenter autoscaler |
| `enable_ClusterAutoscaler` | `false` | Enable Cluster Autoscaler |

---

## Step 4 — Configure Application Secrets

Open [deploy-as-code/helm/environments/egov-demo-secrets.yaml](deploy-as-code/helm/environments/egov-demo-secrets.yaml).

> **No SSH key needed.** DIGIT 3 services do not use git-sync. MDMS data is stored in PostgreSQL via the `mdms-v2` service. The `git-sync` block in the secrets file is a legacy 2.x artifact — leave it empty or remove it.

### 4a. Required secrets to fill in

#### Database credentials
```yaml
cluster-configs:
  secrets:
    db:
      username: <your_db_username>        # alphanumeric only
      password: <your_db_password>        # choose a strong password
      flywayUsername: <your_db_username>
      flywayPassword: <your_db_password>
```

#### AWS S3 credentials (for file storage)
```yaml
    egov-filestore:
      aws-key: <your_aws_access_key>
      aws-secret-key: <your_aws_secret_key>
```

> These should be the IAM access keys for a user that has S3 read/write access on your filestore bucket.

#### New in DIGIT 3 — Elasticsearch credentials
```yaml
    elasticsearch-master-creds:
      password: <choose_a_strong_password>
```

#### New in DIGIT 3 — Kafka Kraft cluster ID
Generate a unique base64 cluster ID (22 characters):
```bash
cat /dev/urandom | tr -dc 'A-Za-z0-9' | head -c 22
```
```yaml
    kafka-kraft:
      kraft-cluster-id: <22-char-alphanumeric-id>
```

#### New in DIGIT 3 — OAuth2 Proxy (for dashboard access)
```yaml
    oauth2-proxy:
      clientID: <github-oauth-app-client-id>
      clientSecret: <github-oauth-app-client-secret>
      cookieSecret: <32-byte-base64-secret>   # generate: openssl rand -base64 32
```

### 4b. Optional secrets (fill in as needed)

| Secret block | Purpose |
|---|---|
| `egov-notification-sms` | SMS notifications |
| `egov-location.gmapskey` | Google Maps integration |
| `egov-pg-service` | Axis / PayU payment gateway |
| `pgadmin` | PgAdmin UI access |
| `egov-enc-service` | Data encryption service |
| `egov-notification-mail` | Email notifications |
| `kibana` | Kibana dashboard access |
| `egov-si-microservice` | Finance service |
| `egov-edcr-notification` | eDCR notifications |
| `chatbot` | Chatbot integration |

### 4c. Update domain and DB host in egov-demo.yaml

Open [deploy-as-code/helm/environments/egov-demo.yaml](deploy-as-code/helm/environments/egov-demo.yaml) and replace the placeholders:

```yaml
global:
  domain: "<your-domain-name>"   # same as domain_name in input.yaml

cluster-configs:
  configmaps:
    egov-config:
      data:
        db-host: "postgres.backbone"         # in-cluster PostgreSQL host
        db-name: "<your_db_name>"            # name for the DIGIT database
        db-url: "jdbc:postgresql://postgres.backbone/<your_db_name>"
        domain: "<your-domain-name>"
        egov-services-fqdn-name: "https://<your-domain-name>/"
```

---

## Step 5 — GitHub Actions Workflow

> **Nothing to do here.** The workflow file [.github/workflows/digit-install.yaml](.github/workflows/digit-install.yaml) is already committed in the `digit3-infra` branch. When you fork the repository, the workflow comes with it automatically — you do not need to create or modify it.

The workflow runs three jobs in sequence when you push to `digit3-infra`:

1. **Input_validation** — reads `input.yaml`, runs the Terraform init script, archives artifacts
2. **Terraform_Infra_Creation** — provisions EKS cluster, VPC, KMS key, node group, and remote state S3 bucket
3. **DIGIT_Deployment** — installs Helm, Helmfile, SOPS, then deploys all DIGIT 3 services

A fourth job, **terraform_infra_destruction**, runs only when manually triggered with the input `destroy` — used for cleanup.

To view the full workflow file, see [.github/workflows/digit-install.yaml](.github/workflows/digit-install.yaml).

---

## Step 6 — Trigger Installation

Commit and push all changes to the `digit3-infra` branch:

```bash
git add .github/workflows/digit-install.yaml
git add infra-as-code/terraform/sample-aws/input.yaml
git add deploy-as-code/helm/environments/egov-demo.yaml
git add deploy-as-code/helm/environments/egov-demo-secrets.yaml
git commit -m "Configure DIGIT 3 deployment parameters"
git push origin digit3-infra
```

Open the **Actions** tab in your GitHub repository. The `DIGIT-Install workflow` pipeline will start automatically. The jobs run in sequence:

1. **Input_validation** — validates `input.yaml` and archives artifacts
2. **Terraform_Infra_Creation** — provisions the EKS cluster, VPC, KMS key, and node group
3. **DIGIT_Deployment** — deploys all DIGIT 3 services via Helmfile

Monitor each job for errors. A green checkmark on all three jobs means the installation succeeded.

---

## Step 7 — KubeConfig Setup (Local Access)

To access your cluster from your local machine after deployment:

### Configure AWS CLI

If not already done:

```bash
aws configure --profile <profile_name>
# Enter your AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and region when prompted
```

Export the profile:

```bash
export AWS_PROFILE=<profile_name>
```

Verify credentials:

```bash
aws configure list --profile <profile_name>
```

### Update kubeconfig

```bash
aws eks --region ap-south-1 update-kubeconfig --name <cluster_name>
```

### Verify cluster access

```bash
kubectl config use-context <cluster_name>
kubectl get nodes
kubectl get pods -A
```

### Get the LoadBalancer hostname

```bash
kubectl get svc ingress-nginx-controller -n backbone \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

The output will be something like:

```
ae210873da6ff4c03bde2ad22e18fe04-233d3411.ap-south-1.elb.amazonaws.com
```

---

## Step 8 — DNS Configuration

Add a **CNAME record** in your domain provider pointing your domain to the LoadBalancer hostname obtained in Step 8.

| Type | Name | Value |
|---|---|---|
| CNAME | `<your-domain-name>` | `<loadbalancer-hostname>.ap-south-1.elb.amazonaws.com` |

DNS propagation can take a few minutes to a few hours depending on your provider.

---

## Step 9 — Post Deployment

Once DNS propagates, access the DIGIT employee dashboard:

```
https://<your-domain-name>/employee
```

> **DIGIT 3 uses Keycloak for authentication** (replaced the Zuul-based auth from 2.9 LTS). Use the admin credentials configured in `egov-demo-secrets.yaml` to log in for the first time.

Verify core services are running:

```bash
kubectl get pods -n egov
kubectl get pods -n backbone
kubectl get pods -n cert-manager
```

---

## Step 10 — Cleanup and Uninstallation

When you are ready to destroy the infrastructure:

1. Navigate to **Actions** in your GitHub repository.
2. Click **DIGIT-Install workflow**.
3. Click **Run workflow**.
4. Type `destroy` in the input field and confirm.

The `terraform_infra_destruction` job will:
- Delete the `ingress-nginx-controller` service (releases the AWS Load Balancer)
- Run `terraform destroy` on the main infrastructure
- Remove the EKS cluster, VPC, node groups, and KMS key

Monitor the Actions window for completion. A success message confirms all resources have been removed.

> **Important:** If DIGIT is installed from a branch other than `digit3-infra`, update the `branches` list in `.github/workflows/digit-install.yaml` to include the correct branch name before triggering the destroy workflow.

---

## Reference: What Terraform Creates

| Resource | Details |
|---|---|
| VPC | CIDR `10.30.0.0/16`, subnets in `ap-south-1a` and `ap-south-1b` |
| EKS Cluster | Kubernetes 1.33, public + private endpoint access |
| Node Group | Spot instances, `m5a.xlarge` (x86) or `t4g.xlarge` (ARM), AL2023 AMI |
| EBS CSI Driver | gp3 encrypted volumes, set as default StorageClass |
| KMS Key | Used by SOPS to encrypt `egov-demo-secrets.yaml` |
| S3 Bucket | Stores Terraform state |
| DynamoDB Table | Terraform state locking |

## Reference: Secrets File Comparison

| Secret | 2.9 LTS location | DIGIT 3 location |
|---|---|---|
| DB credentials | `env-secrets.yaml` | `egov-demo-secrets.yaml` |
| git-sync SSH key | `env-secrets.yaml` | **Not required** — DIGIT 3 has no git-sync |
| EC2 SSH public key | `input.yaml` | **Not required** — nodes use AWS SSM |
| S3 filestore keys | `env-secrets.yaml` | `egov-demo-secrets.yaml` |
| Elasticsearch password | Not present | `egov-demo-secrets.yaml` |
| Kafka Kraft cluster ID | Not present | `egov-demo-secrets.yaml` |
| OAuth2-proxy secrets | Not present | `egov-demo-secrets.yaml` |
| Keycloak credentials | Not present | `egov-demo-secrets.yaml` / `egov-demo.yaml` |
