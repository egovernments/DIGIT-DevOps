output "azurerm_postgresql_flexible_server" {
  value = "${azurerm_postgresql_flexible_server.default.name}"
}

output "postgresql_flexible_server_database_name" {
  value = "${azurerm_postgresql_flexible_server_database.default.name}"
}

output "postgresql_flexible_server_admin_password" {
  value     = "${azurerm_postgresql_flexible_server.default.administrator_password}"
}