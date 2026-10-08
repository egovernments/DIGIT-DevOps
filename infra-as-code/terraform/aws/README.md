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

## What's New in Kubernetes 1.35

Kubernetes 1.35 ("Timbernetes") upstream highlights relevant to DIGIT workloads (verify feature availability against the EKS 1.35 support matrix before relying on any of them):

- **cgroup v1 support removed**: nodes must run cgroup v2. EKS-optimized AL2023 AMIs already default to cgroup v2, so default managed node groups need no action; any custom AMI or bootstrap must be on cgroup v2 before upgrading.
- **In-place Pod resource resize is GA**: adjust container CPU/memory without restarting the Pod.
- **PreferSameNode / PreferSameZone traffic distribution**: Services can prefer local endpoints first, reducing latency and cross-AZ data cost.
- **kube-proxy IPVS mode deprecated**: nftables is the long-term replacement. The default EKS kube-proxy add-on (iptables mode) is unaffected.
- **kubeadm v1beta3 config API removed**: not used by the EKS managed control plane.
- **DRAResourceHealth v1alpha1 deprecated** (removal targeted for 1.40).
- Note: ingress-nginx receives best-effort maintenance only until March 2026; plan a migration path if DIGIT ingress relies on it.

Official release notes: https://kubernetes.io/blog/2025/12/17/kubernetes-v1-35-release/ · CHANGELOG: https://github.com/kubernetes/kubernetes/blob/master/CHANGELOG/CHANGELOG-1.35.md · EKS 1.35 availability: https://aws.amazon.com/about-aws/whats-new/2026/01/amazon-eks-distro-kubernetes-version-1-35/

## Kubernetes 1.35 — Terraform Code Changes (EKS 1.34 → 1.35)

Code/config changes made for the 1.34 → 1.35 upgrade:

- `kubernetes_version` default bumped from `1.34` to `1.35` in `variables.tf`.
- EKS and the managed node group are provisioned through `terraform-aws-modules/eks/aws` and its `eks-managed-node-group` submodule pinned to `~> 21.0` (no module bump needed for 1.35). The module resolves the correct EKS-optimized **AL2023** AMI for the cluster version automatically via `ami_type` (from `ami_type_map`), so no version-specific AMI ID is pinned and AL2023 satisfies the new cgroup v2 requirement.
- Managed EKS add-ons (`vpc-cni`, `coredns`, `kube-proxy`, `aws-ebs-csi-driver`) are declared with `resolve_conflicts_on_create/on_update = "OVERWRITE"` so they upgrade in step with the control plane.
- Optional `enable_karpenter` and `enable_ClusterAutoscaler` toggles remain available; the Karpenter `EC2NodeClass` uses `alias: al2023@latest`, so new nodes roll onto the 1.35 AL2023 AMI automatically.

## Upgrading from 1.34 to 1.35

> EKS upgrades one minor version at a time. The cluster must already be on **1.34** before upgrading to **1.35**.

1. **Bump the version** — `kubernetes_version = "1.35"` (already the default in `variables.tf`).
2. **Upgrade the control plane**
   ```bash
   terraform init
   terraform plan  -var='db_password=<password>'
   terraform apply -var='db_password=<password>'
   ```
3. **Validate**
   ```bash
   kubectl get nodes        # every node reports v1.35.x
   kubectl version
   kubectl get pods -A      # coredns, kube-proxy, vpc-cni, ebs-csi healthy
   ```
4. If Karpenter is enabled, confirm drifted nodes are replaced and new nodes come up on the 1.35 AL2023 AMI (`alias: al2023@latest`).

## Important Inputs

Update `input.yaml` first. The values are substituted into Terraform placeholders by the init helper.

Required values:

- `cluster_name`: EKS cluster and environment name.
- `db_name`: PostgreSQL database name.
- `db_username`: PostgreSQL admin user.
- `terraform_state_bucket_name`: S3 bucket used for Terraform state and the DynamoDB lock table name.

These values are validated against the relevant AWS naming rules (EKS cluster name, RDS DB name/user, S3 bucket name) when you run `terraform plan`, so a bad value fails fast with a clear message. The exact constraints and examples are documented inline in `input.yaml`. `db_password` must be 8 to 16 characters, start with a lowercase letter, and use only letters, numbers and `#` (RDS does not allow `@`).

Review `variables.tf` for version, sizing, and autoscaling defaults before applying:

- `kubernetes_version` defaults to `1.35`.
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
