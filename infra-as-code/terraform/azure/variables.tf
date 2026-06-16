variable "environment" {
  description = "The environment tag for Azure resources"
  type        = string
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

variable "location" {}

variable "db_version" {
    default = "15"
}

variable "db_user" {
  description = "Azure DB User name"
  type        = string

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
    can(regex("^[a-z][a-z0-9@#]$", var.db_password))
    )
    error_message = <<EOT
DB password must:
- Be 6 to 16 characters long
- Start with a lowercase letter
- Use only lowercase letters, numbers, and @ or # (no other symbols)
EOT
  }
}