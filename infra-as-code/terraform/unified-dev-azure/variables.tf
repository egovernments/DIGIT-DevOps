variable "environment" {
  description = "The environment tag for Azure resources"
  type        = string
  default     = "unified-dev"
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
  default     = "unified-dev-rg"

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

variable "db_version" {
  description = "PostgreSQL Flexible Server engine version"
  default     = "15"
}

variable "kubernetes_version" {
  description = "AKS version"
  default     = "1.34"
}

variable "db_user" {
  description = "Azure DB User name"
  type        = string
  default     = "unifieddev"

  validation {
    condition = (
      length(var.db_user) >= 3 &&
      length(var.db_user) <= 40 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.db_user)) &&
      !can(regex("--", var.db_user)) # no consecutive hyphens
    )
    error_message = <<EOT
DB User name must:
- Be 3 to 40 characters long
- Contain only lowercase letters & numbers
- Start with a lowercase letter
EOT
  }
}

variable "db_password" {
  description = "Azure DB password"
  type        = string

  validation {
    condition = (
      length(var.db_password) >= 6 &&
      length(var.db_password) <= 16 &&
      can(regex("^[a-z][a-zA-Z0-9@#]*$", var.db_password))
    )
    error_message = <<EOT
DB password must:
- Be 6 to 16 characters long
- Start with a lowercase letter
- Use only letters, numbers, and @ or # (no other symbols)
EOT
  }
}


variable "vnet_address_space" {
  description = "CIDR range for the Azure virtual network"
  default     = ["10.0.0.0/16"]
}

variable "aks_address_prefixes" {
  description = "CIDR range for the AKS subnet"
  default     = ["10.0.0.0/21"]
}

variable "postgres_address_prefixes" {
  description = "CIDR range for the PostgreSQL subnet"
  default     = ["10.0.8.0/21"]
}

# ---- Node pools ----
variable "system_vm_size" {
  description = "VM size for the small always-on System node pool (default_node_pool)"
  default     = "Standard_B2s" # 2 vCPU, 4 GiB
}

variable "system_node_count" {
  description = "Number of nodes in the always-on System node pool"
  default     = 1
}

variable "main_vm_size" {
  description = "VM size for the main User node pool that runs workloads"
  default     = "Standard_D4s_v3" # 4 vCPU, 16 GiB
}

variable "node_count" {
  description = "Desired number of nodes in the main User node pool"
  default     = 8
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB for AKS worker nodes"
  default     = 64
}

variable "db_sku_name" {
  description = "SKU name for the Azure PostgreSQL Flexible Server"
  default     = "B_Standard_B2ms"
}

variable "db_storage_mb" {
  description = "Allocated storage size in MB for the PostgreSQL Flexible Server"
  default     = "65536"
}

variable "db_backup_retention_days" {
  description = "Number of days to retain PostgreSQL backups"
  default     = "7"
}

# ---- Scheduling (stop the cluster at night / start it in the morning) ----
variable "scheduling" {
  description = "When true, create Azure Automation + runbook + schedules to stop the AKS cluster at night and start it in the morning. Cluster stop/start is used rather than draining the node pool to 0, because draining cannot satisfy the Elasticsearch PDBs."
  type        = bool
  default     = true
}

variable "subscription_id" {
  description = "Azure subscription ID (used by the scheduling runbook to select the context)"
  type        = string
  default     = "777e3e4b-0998-4759-adc2-e7b5b19a6b28"
}

variable "scale_up_time" {
  description = "Local wall-clock time (HH:MM) to start the cluster"
  type        = string
  default     = "08:30"
}

variable "scale_down_time" {
  description = "Local wall-clock time (HH:MM) to stop the cluster"
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


