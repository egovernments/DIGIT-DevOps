output "azurerm_postgresql_flexible_server" {
  value = module.postgres-db.azurerm_postgresql_flexible_server
}

output "postgresql_flexible_server_database_name" {
  value = module.postgres-db.postgresql_flexible_server_database_name
}

output "resource_group"{
  value = var.resource_group
}

output "db_user" {
  value = var.db_user
}

output "cluster_name" {
  value = var.environment
}
