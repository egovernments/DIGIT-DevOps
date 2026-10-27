variable "subscription_id" {
  description = "Azure subscription that hosts the sandbox"
  default     = "777e3e4b-0998-4759-adc2-e7b5b19a6b28"
}

variable "resource_group" {
  description = "Resource group holding the sandbox and its tfstate"
  default     = "k3s-sandbox-rg"
}

variable "location" {
  description = "Azure region"
  default     = "centralindia"
}

variable "environment" {
  description = "Environment name, also used for the state container"
  default     = "k3s-sandbox"
}
