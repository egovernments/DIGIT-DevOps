variable "environment" {
    default = "demo-azure-terraform"
}
variable "resource_group" {
    default = "demo-azure-rg-terraform"
}

variable "location" {
    default = "South India"
}

variable "db_version" {
    default = "15"
}

variable "db_user" {
    default = "azurepostgres"
}

variable "db_password"{}
variable "subscription_id" {
  description = "The Subscription ID for Azure"
  type        = string
}

variable "tenant_id" {
  description = "The Tenant ID for Azure Active Directory"
  type        = string
}

variable "client_id" {
  description = "The Client ID for Azure Active Directory Application"
  type        = string
}

variable "client_secret" {
  description = "The Client Secret for Azure Active Directory Application"
  type        = string
  sensitive   = true
}
