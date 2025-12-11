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
  | karpenter | ~> 20.0 |  21.3.1 |

---

## 2️⃣ Architecture Flexibility
- Terraform now supports **AMD (x86_64)** and **ARM (arm64)** architectures for worker nodes.
- Architecture is selected using the `architecture` variable in `variables.tf`:

```hcl
variable "architecture" {
  description = "Architecture for worker nodes (x86_64 or arm64)"
  type        = string
  default     = "x86_64"
  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "Architecture must be either x86_64 or arm64."
  }
}
```
- **Default instance types** are mapped to architecture using `instance_types_map`:
```hcl
variable "instance_types_map" {
  description = "Map of instance types per architecture"
  type        = map(list(string))
  default = {
    x86_64 = ["m5a.xlarge"]
    arm64  = ["t4g.xlarge"]
  }
}
```
- **Optional override:** Provide custom instance types in `instance_types` to override defaults:
```hcl
variable "instance_types" {
  description = "List of instance types to use (optional — overrides architecture defaults)"
  type        = list(string)
  default     = []
}
```

## 3️⃣ AMI Upgrade
- Node group AMI upgraded from Amazon Linux 2 (AL2) → Bottlerocket for improved:
    - Security
    - Performance
    - Container-optimized operations
    
## 4️⃣ Provider & Dependency Fixes
- Fixed the `kubectl` provider issue where multiple `terraform apply` executions failed due to context mismatch.
- Updated kubectl provider to version >= 2.0.2.

## 5️⃣ Addon & Module Enhancements
- Added EBS CSI Controller addon with IRSA support to enable secure IAM-based access to EBS volumes.
- Added Cluster Autoscaler module `(lablabs/eks-cluster-autoscaler/aws)` to dynamically scale node groups based on workload demand.
- Updated Karpenter Helm chart version from `v1.5.0` → `v1.8.1` for enhanced node provisioning and lifecycle improvements.
- Added `eks-pod-identity-agent` addon to simplify IAM role assignment for pods when Karpenter is enabled.

## 6️⃣ Key Benefits
- Multi-architecture support (ARM + AMD) for broader instance type compatibility.
- Bottlerocket AMIs for container-optimized performance and security.
- Simplified scaling with both Karpenter and Cluster Autoscaler integration.
- Stronger IAM isolation using IRSA-based service accounts.

## 📚 Documentation

Refer to our [Core Infrastructure Documentation](https://core.digit.org/guides/installation-guide/infrastructure-setup/aws/3.-provision-infrastructure) to deploy the infrastructure end-to-end.
