# EKS v1.32 Upgrade - Summary of Changes

As part of the **EKS upgrade to Kubernetes v1.32**, the following updates and enhancements were implemented.

---

## 1️⃣ Core Upgrades
- **Kubernetes version:** `v1.31` → `v1.32`  
- **Terraform module upgrades:**
  | Module | Previous Version | Upgraded Version |
  |--------|-----------------|----------------|
  | terraform-aws-eks | ~> 20.0 | ~> 21.0 |
  | eks-managed-node-group | ~> 20.0 | ~> 21.0 |
  | karpenter | ~> 20.0 | ~> 21.0 |

---

## 2️⃣ Architecture Flexibility
- Terraform now supports **AMD (x86_64)** and **ARM (arm64)** architectures.
- Architecture type is **dynamically selected** via `variables.tf` using the `architecture` variable.
- Corresponding **AMI types and instance types** are automatically selected:

```hcl
ami_type_map = {
  x86_64 = "BOTTLEROCKET_x86_64"
  arm64  = "BOTTLEROCKET_ARM_64"
}
```
## 3️⃣ AMI Upgrade
- **Node group AMI upgraded from Amazon Linux 2 (AL2) → Bottlerocket for improved:
    **Security
    **Performance
    **Container-optimized operations
    
## 4️⃣ Provider & Dependency Fixes
- **Fixed the `kubectl` provider issue where multiple `terraform apply` executions failed due to context mismatch.
- **Updated kubectl provider to version >= 2.0.2.

## 5️⃣ Addon & Module Enhancements
- **Added EBS CSI Controller addon with IRSA support to enable secure IAM-based access to EBS volumes.
- **Added Cluster Autoscaler module `(lablabs/eks-cluster-autoscaler/aws)` to dynamically scale node groups based on workload demand.
- **Updated Karpenter Helm chart version from `v1.5.0` → `v1.8.1` for enhanced node provisioning and lifecycle improvements.
- **Added `eks-pod-identity-agent` addon to simplify IAM role assignment for pods when Karpenter is enabled.

## 6️⃣ Key Benefits
- **Multi-architecture support (ARM + AMD) for broader instance type compatibility.
- **Bottlerocket AMIs for container-optimized performance and security.
- **Simplified scaling with both Karpenter and Cluster Autoscaler integration.
- **Stronger IAM isolation using IRSA-based service accounts.

## 📚 Documentation

Refer to our [Core Infrastructure Documentation](https://core.digit.org/guides/installation-guide/infrastructure-setup/aws/3.-provision-infrastructure) to deploy the infrastructure end-to-end.
