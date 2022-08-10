resource "azurerm_postgresql_server" "postgresql_server" {
  name                = "${var.server_name}"
  location             = "${var.location}"
  resource_group_name  = "${var.resource_group}"

  

  administrator_login              = "${var.administrator_login}"
  administrator_login_password     = "${var.administrator_login_password}"

  sku_name                         = "${var.sku_tier}"
  version                          = "${var.db_version}"
  storage_mb                       = "${var.storage_mb}"

  backup_retention_days            = "${var.backup_retention_days}"
  geo_redundant_backup_enabled     = false

  ssl_enforcement_enabled          = "${var.ssl_enforce}"
  ssl_minimal_tls_version_enforced = "TLSEnforcementDisabled"


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