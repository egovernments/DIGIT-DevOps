output "azurerm_postgresql_flexible_server" {
  value = "${azurerm_postgresql_flexible_server.postgresql_server.fqdn}"
}

output "postgresql_flexible_server_database_name" {
  value = "${azurerm_postgresql_flexible_server_database.db.name}"
}