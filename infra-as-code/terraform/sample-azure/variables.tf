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
