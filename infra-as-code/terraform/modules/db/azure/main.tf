resource "azurerm_postgresql_server" "postgresql_server" {
  name                = "${var.server_name}"
  location             = "${var.location}"
  resource_group_name  = "${var.resource_group}"

  sku_name = "${var.sku_tier}"

  storage_profile {
    storage_mb            = "${var.storage_mb}"
    backup_retention_days = "${var.backup_retention_days}"
    geo_redundant_backup  = "Disabled"
  }

  administrator_login          = "${var.administrator_login}"
  administrator_login_password = "${var.administrator_login_password}"
  version                      = "10"
  ssl_enforcement              = "${var.ssl_enforce}"

  tags = {
    environment = "${var.environment}"
  }

}

resource "azurerm_postgresql_database" "db" {
  name                = "${var.db_name}"
  resource_group_name = "${var.resource_group}"
  server_name         = "${azurerm_postgresql_server.postgresql_server.name}"
  charset             = "UTF8"
  collation           = "English_United States.1252"
}