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

## What's New in Kubernetes 1.34

Upstream highlights relevant to DIGIT workloads (verify feature availability against the EKS 1.34 support matrix before relying on any of them):

- **Dynamic Resource Allocation (DRA) core is GA** — standardized requesting and sharing of GPUs and other specialized devices.
- **In-place Pod vertical resource resize** continues to mature — adjust container CPU/memory without a restart.
- **Pod-level resource requests and limits** — resources can be declared at the Pod scope, not only per container.
- **Structured authentication configuration** graduated — cleaner multi-issuer / OIDC auth.
- **Ordered (orderly) namespace deletion** — safer teardown order for namespaced objects.
- **Fine-grained SupplementalGroups control** for Pod security.
- **KYAML** — a stricter, safer YAML output format available in `kubectl`.
- **`.kuberc`** — user-level `kubectl` preferences file.
- Continued API deprecations/removals; the in-tree AWS cloud provider is no longer used (the external AWS cloud controller / add-ons are standard).

Official release notes: https://kubernetes.io/blog/2025/08/27/kubernetes-v1-34-release/ · CHANGELOG: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.34.md

## Kubernetes 1.34 — Terraform Code Changes (EKS 1.33 → 1.34)

Code/config changes made for the 1.33 → 1.34 upgrade:

- `kubernetes_version` default bumped from `1.33` to `1.34` in `variables.tf`.
- EKS and the managed node group are provisioned through `terraform-aws-modules/eks/aws` and its `eks-managed-node-group` submodule pinned to `~> 21.0`. The module resolves the correct EKS-optimized **AL2023** AMI for the cluster version automatically via `ami_type` (from `ami_type_map`), instead of pinning a version-specific 1.33 AMI ID.
- Managed EKS add-ons (`vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`) are declared with `resolve_conflicts_on_create/on_update = "OVERWRITE"` so they upgrade in step with the control plane.
- Optional `enable_karpenter` and `enable_ClusterAutoscaler` toggles remain available; when Karpenter is enabled its `EC2NodeClass` AMI selection must target 1.34.

## Upgrading from 1.33 to 1.34

> EKS upgrades one minor version at a time. The cluster must already be on **1.33** before upgrading to **1.34**.

1. **Bump the version** — `kubernetes_version = "1.34"` (already the default in `variables.tf`).
2. **Upgrade the control plane**
   ```bash
   terraform init
   terraform plan  -var='db_password=<password>'
   terraform apply -var='db_password=<password>'
   ```
3. **Validate**
   ```bash
   kubectl get nodes        # every node reports v1.34.x
   kubectl version
   kubectl get pods -A      # coredns, kube-proxy, vpc-cni, ebs-csi healthy
   ```
4. If Karpenter is enabled, update the `EC2NodeClass` AMI/alias to 1.34 and confirm new nodes come up on 1.34.

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
