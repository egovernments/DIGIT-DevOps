variable "environment" {
  description = "The environment tag for Azure resources"
  type        = string
  default     = "digit-lts"
  validation {
    condition = (
      length(var.environment) >= 3 &&
      length(var.environment) <= 40 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.environment)) &&
      !can(regex("--", var.environment)) # no consecutive hyphens
    )
    error_message = <<EOT
Environment name must:
- Be 3 to 40 characters long
- Contain only lowercase letters, numbers, and hyphens
- Start with a lowercase letter
- Not start or end with a hyphen
- Not contain consecutive hyphens
EOT
  }
}

variable "resource_group" {
  description = "Azure Resource Group name"
  type        = string
  default     = "digit-lts"

  validation {
    condition = (
      length(var.resource_group) >= 3 &&
      length(var.resource_group) <= 40 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.resource_group)) &&
      !can(regex("--", var.resource_group)) # no consecutive hyphens
    )
    error_message = <<EOT
Resource group name must:
- Be 3 to 40 characters long
- Contain only lowercase letters, numbers, and hyphens
- Start with a lowercase letter
- Not start or end with a hyphen
- Not contain consecutive hyphens
EOT
  }
}

variable "location" {
  description = "Azure region where resources will be deployed"
  default     = "centralindia"
}

variable "kubernetes_version" {
  description = "AKS version"
  default     = "1.35"
}


variable "vnet_address_space" {
  description = "CIDR range for the Azure virtual network"
  default     = ["10.0.0.0/16"]
}

variable "aks_address_prefixes" {
  description = "CIDR range for the AKS subnet"
  default     = ["10.0.0.0/21"]
}

# DO NOT CHANGE on the existing cluster. default_node_pool.name cannot be cycled
# via temporary_name_for_rotation, so renaming it makes Terraform DESTROY AND
# RECREATE the entire AKS cluster. This is the name digit-lts already runs.
variable "node_pool_name" {
  description = "Name of the node pool (must match the live cluster)"
  default     = "defaultpool"
}

variable "vm_size" {
  description = "Azure VM size for the AKS node pool"
  default     = "Standard_D4as_v5" # 4 vCPU, 16 GiB
}

# Left at the live cluster's current size so this apply does not move any pods.
# Measured requests are 51.5 GiB memory / 17.1 vCPU, which would fit on 5 nodes,
# but observed working-set memory is ~73 GiB, so shrinking is a separate decision.
# Lowering this is an in-place scale (cordon + drain), not a rotation.
variable "node_count" {
  description = "Number of nodes in the AKS node pool"
  default     = 7
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB for AKS worker nodes"
  default     = 64
}

# ---- Cluster scheduling (stopped overnight) ----

variable "scheduling" {
  description = "When true, create Azure Automation + runbook + schedules that stop the cluster at night and start it in the morning"
  type        = bool
  default     = true
}

variable "subscription_id" {
  description = "Azure subscription ID (used by the scheduling runbook to select the context)"
  type        = string
  default     = "777e3e4b-0998-4759-adc2-e7b5b19a6b28"
}

variable "cluster_start_time" {
  description = "Local wall-clock time (HH:MM) to START the cluster"
  type        = string
  default     = "08:30"
}

variable "cluster_stop_time" {
  description = "Local wall-clock time (HH:MM) to STOP the cluster (deallocates every node)"
  type        = string
  default     = "21:00"
}

variable "schedule_timezone" {
  description = "IANA timezone the schedules run in (e.g. Asia/Kolkata)"
  type        = string
  default     = "Asia/Kolkata"
}

variable "schedule_utc_offset" {
  description = "UTC offset of schedule_timezone, used to build the first run time (e.g. +05:30 for IST)"
  type        = string
  default     = "+05:30"
}

variable "schedule_week_days" {
  description = "Days the start/stop schedules run on. Defaults to weekdays so the cluster stays stopped all weekend"
  type        = list(string)
  default     = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]
}

# ---- Settings that already exist on the live digit-lts cluster ----
# The azurerm provider defaults all of these to off/absent. If they are not set
# here, `terraform plan` shows them being DISABLED, which would break workload
# identity and take cluster authorization off Entra ID RBAC.

variable "oidc_issuer_enabled" {
  description = "OIDC issuer (required by workload identity). Live cluster: true"
  type        = bool
  default     = true
}

variable "workload_identity_enabled" {
  description = "Azure AD Workload Identity. Live cluster: true"
  type        = bool
  default     = true
}

variable "azure_rbac_enabled" {
  description = "Use Azure RBAC for Kubernetes authorization. Live cluster: true"
  type        = bool
  default     = true
}

variable "aad_tenant_id" {
  description = "Entra ID tenant for AKS-managed Entra integration. Empty disables the block"
  type        = string
  default     = "593ce202-d1a9-4760-ba26-ae35417c00cb"
}

variable "node_pool_max_surge" {
  description = "Surge nodes during a node pool upgrade. Live cluster: 10%"
  type        = string
  default     = "10%"
}
