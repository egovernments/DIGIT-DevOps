provider "azurerm" {
  subscription_id            = var.subscription_id
  tenant_id                  = var.tenant_id
  client_id                  = var.client_id
  client_secret              = var.client_secret
  features {}
  
  # Updated: skip_provider_registration is deprecated, consider removing in future versions
  skip_provider_registration = true
}

resource "azurerm_resource_group" "resource_group" {
  name     = var.resource_group
  location = var.location
  tags = {
     environment = var.environment
  }
}

resource "random_string" "resource_code" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_storage_account" "tfstate" {
  name                     = "tfstate${random_string.resource_code.result}"
  resource_group_name      = azurerm_resource_group.resource_group.name
  location                 = azurerm_resource_group.resource_group.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  allow_nested_items_to_be_public = false

  tags = {
    environment = var.environment
  }

  depends_on = [azurerm_resource_group.resource_group]
}

resource "azurerm_storage_container" "tfstate" {
  name                  = var.tfstate
  storage_account_name  = azurerm_storage_account.tfstate.name
  container_access_type = "private"
}