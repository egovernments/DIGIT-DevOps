# Define Azure authentication variables
variable "subscription_id" {
  description = "The subscription ID to use for Azure"
  default = "d5fae6d0-9ecb-40a9-b66b-7583559ce79e"
}

variable "tenant_id" {
  description = "The tenant ID to use for Azure"
  default = "593ce202-d1a9-4760-ba26-ae35417c00cb"
}

variable "client_id" {
  description = "The client ID for the Azure service principal"
  default = "7cc44878-cfd6-4eb9-ab24-e5e855786224"
}

variable "client_secret" {
  description = "The client secret for the Azure service principal"
  default = "jb38Q~0.F2yg1TWdUA7lE4yjQggCcJSocJWtCcgu"
}

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
