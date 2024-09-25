

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

