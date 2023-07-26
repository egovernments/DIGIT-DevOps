output "db_host" {
  value = azurerm_postgresql_server.postgresql_server.fqdn
}

output "db_name" {
  value = azurerm_postgresql_database.db.name
}
