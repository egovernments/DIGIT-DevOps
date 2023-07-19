output "db_host" {
  value = azurerm_postgresql_server.postgresql_server.fully_qualified_domain_name
}

output "db_name" {
  value = azurerm_postgresql_database.db.name
}
