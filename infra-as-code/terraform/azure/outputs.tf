output "resource_group" {
  value = var.resource_group
}

output "cluster_name" {
  value = var.environment
}

output "azurerm_postgresql_flexible_server" {
  value = module.postgres-db.azurerm_postgresql_flexible_server
}

output "postgresql_flexible_server_database_name" {
  value = module.postgres-db.postgresql_flexible_server_database_name
}

output "db_user" {
  value = var.db_user
}

output "filestore_storage_account_name" {
  value = azurerm_storage_account.filestore.name
}

output "filestore_container_name" {
  value = azurerm_storage_container.filestore.name
}

output "public_assets_container_name" {
  value = azurerm_storage_container.public_assets.name
}

output "public_assets_base_url" {
  description = "Base URL for anonymous reads from the public-assets container"
  value       = "${azurerm_storage_account.filestore.primary_blob_endpoint}${azurerm_storage_container.public_assets.name}"
}