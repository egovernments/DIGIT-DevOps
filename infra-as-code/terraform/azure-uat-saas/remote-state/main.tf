provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

# The bootstrap state lives in the storage account this configuration creates.
# Bootstrap once with the local backend, then migrate: terraform init -migrate-state
terraform {
  backend "azurerm" {
    resource_group_name  = "uat-saas"
    storage_account_name = "tfstate0znm8"
    container_name       = "uat-saas-container"
    key                  = "bootstrap.tfstate"
  }
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

  # This account holds the Terraform state for the whole environment. Versioning
  # plus soft delete make a corrupted or deleted state blob recoverable.
  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = {
    environment = var.environment
  }

  depends_on = [azurerm_resource_group.resource_group]
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "${var.environment}-container"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}