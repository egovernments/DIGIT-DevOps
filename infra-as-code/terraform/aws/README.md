# AWS Terraform

This directory provisions the AWS infrastructure required for a DIGIT environment.

## Release Highlights

- Provisions VPC networking through `../modules/network/aws`.
- Provisions PostgreSQL RDS through `../modules/db/aws`.
- Provisions EKS through `terraform-aws-modules/eks/aws` `~> 21.0`.
- Adds an EKS managed node group using AL2023 AMIs.
- Supports `x86_64` and `arm64` worker node architecture selection.
- Adds EBS CSI IRSA, the `gp3` Kubernetes storage class, and managed EKS add-ons.
- Adds optional Karpenter and Cluster Autoscaler toggles.
- Creates an S3 filestore bucket, IAM user, IAM policy, access key, and Kubernetes secret.
- Adds an S3 backend and DynamoDB state-locking bootstrap under `remote-state/`.

## Important Inputs

Update `input.yaml` first. The values are substituted into Terraform placeholders by the init helper.

Required values:

- `cluster_name`: EKS cluster and environment name.
- `db_name`: PostgreSQL database name.
- `db_username`: PostgreSQL admin user.
- `terraform_state_bucket_name`: S3 bucket used for Terraform state and the DynamoDB lock table name.

Review `variables.tf` for version, sizing, and autoscaling defaults before applying:

- `kubernetes_version` defaults to `1.34`.
- `db_version` defaults to `15.18`.
- `architecture` defaults to `x86_64`.
- `enable_karpenter` and `enable_ClusterAutoscaler` default to `false`.

`db_password` is intentionally declared without a default; provide it at plan or apply time.

## Usage

Run the init helper from this directory after updating `input.yaml`:

```bash
cd infra-as-code/terraform/aws
go run ../scripts/init.go
```

Create the remote-state resources first:

```bash
cd remote-state
terraform init
terraform plan
terraform apply
```

Then provision the AWS infrastructure:

```bash
cd ..
terraform init
terraform plan -var='db_password=<password>'
terraform apply -var='db_password=<password>'
```

To update the Helm environment database placeholders after Terraform completes:

```bash
terraform output -json | go run ../scripts/envYAMLUpdater.go
```

## Outputs

Key outputs include:

- `cluster_endpoint`
- `db_instance_endpoint`
- `db_instance_name`
- `db_instance_username`
- `db_instance_port`
- `s3_filestore_bucket`

## Reference

Core infrastructure guide: https://core.digit.org/guides/installation-guide/infrastructure-setup/aws/3.-provision-infrastructure
