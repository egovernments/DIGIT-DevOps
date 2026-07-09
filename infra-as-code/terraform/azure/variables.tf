variable "environment" {
  description = "The environment tag for Azure resources"
  type        = string
  default     = "studio-demo"
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
  default     = "studio-demo"

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

variable "kubernetes_version"{
  description = "AKS version"
  default     = "1.34"
}

variable "db_user" {
  description = "Azure DB User name"
  type        = string
  default     = "studiodemo"

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
    can(regex("^[a-z][a-z0-9@#]*$", var.db_password))
    )
    error_message = <<EOT
DB password must:
- Be 6 to 16 characters long
- Start with a lowercase letter
- Use only lowercase letters, numbers, and @ or # (no other symbols)
EOT
  }
}


variable "vnet_address_space" {
  description = "CIDR range for the Azure virtual network"
  default = ["10.0.0.0/16"]
}

variable "aks_address_prefixes" {
  description = "CIDR range for the AKS subnet"
  default = ["10.0.0.0/21"]
}

variable "postgres_address_prefixes" {
  description = "CIDR range for the PostgreSQL subnet"
  default = ["10.0.8.0/21"]
}

variable "vm_size" {
  description = "Azure VM size for the AKS default node pool"
  default = "Standard_D4as_v5"  # 4vCPU's, 16GB
}

variable "node_count" {
  description = "Number of nodes in the AKS default node pool"
  default = 3
}

variable "os_disk_size_gb" {
  description = "OS disk size in GB for AKS worker nodes"
  default = 64
}

variable "db_sku_name" {
  description = "SKU name for the Azure PostgreSQL Flexible Server"
  default = "B_Standard_B2ms"
}

variable "db_storage_mb" {
  description = "Allocated storage size in MB for the PostgreSQL Flexible Server"
  default = "65536"
}

variable "db_backup_retention_days" {
  description = "Number of days to retain PostgreSQL backups"
  default = "7"
}


