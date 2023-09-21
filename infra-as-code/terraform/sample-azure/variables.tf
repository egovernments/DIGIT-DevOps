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
    default = "13"
}

variable "db_user" {
    default = "azurepostgres"
}

variable "db_password"{}

variable "subscription_id" {
    default = "8d8fadc3-5236-461c-a0ee-00836a75c4d1"
}

variable "tenant_id" {
    default = "d1127efd-6841-40e9-8c06-300f458a7c00"
}

variable "client_id" {
    default = "6a44b3f1-91b8-4c87-b16a-8f8039a73e4e"
}

variable "client_secret" {
    default = "24c8Q~cmEUXWwF22gscwd5tvDVqSRHLhaUZrraI7"
}
