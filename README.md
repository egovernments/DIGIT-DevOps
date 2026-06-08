# Quick Setup (AWS) — DIGIT 3.0

Installation guide for deploying DIGIT 3.0 infrastructure and services via GitHub Actions on AWS.

> **Note:** This setup is for dev and test environments only.
> Postgres runs as an in-cluster pod (no RDS). Keep this repository **private** to protect secrets in environment files.

---

## Overview

A single `git push` triggers the full pipeline:

```
Input_validation → Terraform_Infra_Creation → DIGIT-deployment
```

| Job | What it does |
|-----|-------------|
| `Input_validation` | Reads `input.yaml`, substitutes placeholders in Terraform and Helm environment files, archives artifacts |
| `Terraform_Infra_Creation` | Creates S3+DynamoDB remote state, then provisions VPC, EKS cluster (K8s 1.33), node group, EBS CSI, storage class |
| `DIGIT-deployment` | Creates namespaces and K8s secrets/configmaps, runs `helmfile apply` to deploy backbone + DIGIT 3 services |
| `terraform_infra_destruction` | Manual trigger — destroys all provisioned AWS infrastructure |

---

## Pre-requisites

- AWS account with administrative privilege
- GitHub account

---

## Step 1 — Create IAM User and Generate Access Keys

> Skip this step if you already have an access key and secret key.

1. Create an IAM User with **AdministratorAccess** in your AWS account.
2. Generate an **Access Key** and **Secret Key** for that user.

```
AWS_ACCESS_KEY_ID     = A************FQ
AWS_SECRET_ACCESS_KEY = tqM************************+lfTt
AWS_REGION            = ap-south-1
```

---

## Step 2 — Fork the Repository

1. Fork this repository into your GitHub account.
   - **Uncheck** "Copy the master branch only" so all branches are forked.
2. After forking, go to the **Actions** tab and click **"I understand my workflows, go ahead and enable them"**.

> Keep the forked repository **private**. The environment files contain credentials.

---

## Step 3 — Add GitHub Repository Secrets

Go to: **Repository Settings → Security → Secrets and Variables → Actions → New repository secret**

Add all four secrets:

| Name | Value |
|------|-------|
| `AWS_ACCESS_KEY_ID` | Your IAM access key |
| `AWS_SECRET_ACCESS_KEY` | Your IAM secret key |
| `AWS_DEFAULT_REGION` | `ap-south-1` |
| `AWS_REGION` | `ap-south-1` |

---

## Step 4 — Clone and Switch Branch

```bash
git clone https://github.com/<your-username>/DIGIT-DevOps-3.0.git
cd DIGIT-DevOps-3.0

# The workflow triggers on this branch
git checkout digit3-release-workflow
```

---

## Step 5 — Configure Infrastructure Parameters

Open `infra-as-code/terraform/sample-aws/input.yaml` and fill in your values:

```yaml
# EKS cluster name — lowercase alphanumeric and hyphens only
cluster_name: "my-digit-cluster"

# Domain name for the DIGIT UI
domain_name: "digit.mydomain.com"

# S3 bucket name for Terraform remote state — must be globally unique
terraform_state_bucket_name: "my-digit-cluster-tf-state"

# Postgres database username — alphanumeric only, must start with a letter
db_username: "digituser"
```

| Parameter | Constraint | Example |
|-----------|-----------|---------|
| `cluster_name` | Lowercase alphanumeric + hyphens only | `my-digit-cluster` |
| `domain_name` | Valid domain you control | `digit.mydomain.com` |
| `terraform_state_bucket_name` | Globally unique S3 bucket name | `my-digit-cluster-tf-state` |
| `db_username` | Alphanumeric only, starts with a letter | `digituser` |

> `db_username` is automatically substituted into `egov-demo-secrets.yaml` by the pipeline when `init.go` runs — you only need to set it here.

---

## Step 6 — Configure Application Secrets

Open `deploy-as-code/helm/environments/egov-demo-secrets.yaml` and update the following:

### Database credentials

```yaml
cluster-configs:
    secrets:
        db:
            username: <db_username>     # auto-filled from input.yaml by the pipeline
            password: MyStr0ngPass!     # replace with a strong password
            flywayUsername: <db_username>
            flywayPassword: MyStr0ngPass!
```

Only update the **password** fields. The `<db_username>` placeholders are automatically replaced by `init.go` using the `db_username` value you set in `input.yaml`.

### Other optional secrets

Update `egov-filestore`, `egov-notification-sms`, `egov-notification-mail`, and
`egov-pg-service` as needed for file storage, SMS/email notifications, and
payment gateway integrations. Leave demo values to skip those features.

---

## Step 7 — Trigger the Installation

Push your changes to the `digit3-release-workflow` branch:

```bash
git add infra-as-code/terraform/sample-aws/input.yaml
git add deploy-as-code/helm/environments/egov-demo-secrets.yaml
git commit -m "configure cluster inputs and secrets"
git push origin digit3-release-workflow
```

Go to the **Actions** tab in GitHub to monitor the workflow. Three jobs run in sequence:

1. `Input_validation` — validates inputs and substitutes placeholders
2. `Terraform_Infra_Creation` — provisions EKS cluster (~15–20 min)
3. `DIGIT-deployment` — deploys all services via Helmfile (~10–15 min)

---

## Step 8 — KubeConfig Setup (Post-Install)

Configure your local AWS CLI profile if not already done:

```bash
aws configure --profile <profile_name>
export AWS_PROFILE=<profile_name>

# Verify credentials
aws configure list --profile <profile_name>
```

Fetch and activate the kubeconfig for your new cluster:

```bash
aws eks --region ap-south-1 update-kubeconfig --name <cluster_name>
kubectl config use-context <cluster_name>

# Verify cluster
kubectl get nodes
kubectl get pods -A
```

---

## Step 9 — DNS Configuration

After the `DIGIT-deployment` job completes, get the AWS Load Balancer hostname:

```bash
kubectl get svc ingress-nginx-controller -n backbone \
  -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'
```

The output will look like:

```
ae210873da6ff4c03bde2ad22e18fe04-233d3411.ap-south-1.elb.amazonaws.com
```

Add a **CNAME record** in your DNS provider pointing your `domain_name` to this hostname.

---

## Post Deployment

Once DNS propagates, access the DIGIT employee dashboard:

```
https://<domain_name>/
```

---

## Cleanup — Destroy DIGIT Infrastructure

> This removes **all** AWS resources created by Terraform (EKS, VPC, node group).
> The S3 bucket and DynamoDB table for Terraform state are preserved (`prevent_destroy = true`).

### Steps

1. Go to **Actions** tab in GitHub.
2. Select the **DIGIT-Install workflow**.
3. Click **Run workflow**.
4. In the input field, type exactly: `destroy`
5. Click **Run workflow**.

The `terraform_infra_destruction` job will:
1. Delete the `ingress-nginx-controller` LoadBalancer service (releases the AWS ELB)
2. Run `terraform destroy` to remove all infrastructure

Monitor the job output in the Actions tab. A green checkmark confirms successful destruction.

---

## Infrastructure Summary (What Gets Created)

| Resource | Details |
|----------|---------|
| VPC | CIDR `10.30.0.0/16`, public + private subnets across 2 AZs |
| EKS Cluster | Kubernetes 1.33, API + ConfigMap auth |
| Node Group | `m5a.xlarge` (x86\_64) or `t4g.xlarge` (arm64), min 1 / desired 3 / max 5 |
| EBS CSI Driver | IRSA-based, gp3 storage class (default) |
| KMS Key | For SOPS secret encryption |
| S3 + DynamoDB | Terraform remote state (preserved on destroy) |

## Services Deployed

| Layer | Services |
|-------|---------|
| Backbone | cert-manager, postgresql-lts (in-cluster Postgres), redis, minio, ingress-nginx |
| DIGIT 3 | idgen, mdms-v2, localization, boundary, keycloak, individual, account, registry, rbac, otp, hrms, workflow, notification, filestore, pdf, url-shortener, gateway-kong |
