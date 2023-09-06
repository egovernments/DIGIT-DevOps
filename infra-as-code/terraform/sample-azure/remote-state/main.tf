provider "azurerm" {
  version = "3.71.0"
  features {}
  skip_provider_registration = true
}

resource "azurerm_resource_group" "resource_group" {
  name     = "${var.resource_group}"
  location = "${var.location}"
  tags = {
     environment = "${var.environment}"
  }
}

resource "random_string" "resource_code" {
  length  = 5
  special = false
  upper   = false
}


resource "azurerm_storage_account" "tfstate" {
  name                     = "tfstate${random_string.resource_code.result}"
  resource_group_name      = "${var.resource_group}"
  location                 = "${var.location}"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_nested_items_to_be_public = false

  tags = {
    environment = "${var.environment}"
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "${var.tfstate}"
  storage_account_name  = "${azurerm_storage_account.tfstate.name}"
  container_access_type = "private"
}