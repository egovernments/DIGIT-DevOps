# Other variables
variable "tfstate" {
  description = "The name of the Azure Storage container for Terraform state"
  default     = "demo-azure-container"
}

variable "environment" {
  description = "The environment tag for Azure resources"
  default     = "demo-azure-terraform"
}

variable "location" {
  description = "The location of the resources in Azure"
  default     = "South India"
}

variable "resource_group" {
  description = "The resource group name for the Azure resources"
  default     = "demo-azure-rg-terraform"
}
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