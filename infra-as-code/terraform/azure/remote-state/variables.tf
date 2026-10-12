# Other variables

variable "environment" {
  description = "The environment tag for Azure resources"
  type        = string
  default     = "<environment>"
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

variable "location" {
  default = "<location>"
}

variable "storage_account_name" {
  description = "Globally-unique Azure Storage Account name that holds the Terraform state"
  type        = string
  default     = "<storage_account_name>"
  validation {
    condition = (
      length(var.storage_account_name) >= 3 &&
      length(var.storage_account_name) <= 24 &&
      can(regex("^[a-z0-9]+$", var.storage_account_name))
    )
    error_message = <<EOT
Storage account name must follow Azure naming rules:
- Be 3 to 24 characters long
- Contain only lowercase letters and numbers (no hyphens, underscores or uppercase)
- Be globally unique across all of Azure
EOT
  }
}

variable "resource_group" {
  description = "Azure Resource Group name"
  type        = string
  default     = "<resource_group>"

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