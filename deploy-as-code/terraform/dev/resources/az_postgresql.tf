resource "azurerm_postgresql_server" "az_pgdb" {
  count               = "${var.postgresql["count"]}"
  name                = "${var.project}-${var.env}-az-postgresql-server"
  location            = "${var.location}"
  resource_group_name = "${azurerm_resource_group.main.name}"

  sku {
    name = "B_Gen5_2"
    capacity = 2
    tier = "Basic"
    family = "Gen5"
  }

  storage_profile {
    storage_mb = "${var.postgresql["volume_size"]*1024}"
    backup_retention_days = 7
    geo_redundant_backup = "Disabled"
  }

  administrator_login = "${var.postgresql["admin_username"]}"
  administrator_login_password = "${var.postgresql["admin_password"]}"
  version = "${var.postgresql["version"]}"
  ssl_enforcement = "Disabled"
}

resource "azurerm_postgresql_firewall_rule" "fw_rule" {
  name                = "AzureServices"
  resource_group_name = "${azurerm_resource_group.main.name}"
  server_name         = "${azurerm_postgresql_server.az_pgdb.name}"
  start_ip_address    = "0.0.0.0"
  end_ip_address      = "0.0.0.0"
}
resource "azurerm_postgresql_firewall_rule" "fw_rule_egov" {
  name                = "allow_egov_network"
  resource_group_name = "${azurerm_resource_group.main.name}"
  server_name         = "${azurerm_postgresql_server.az_pgdb.name}"
  start_ip_address    = "106.51.69.20"
  end_ip_address      = "106.51.69.20"
}

resource "azurerm_postgresql_database" "az_db" {
  name                = "${replace(var.project,"-","_")}_${var.env}_azdb"
  resource_group_name = "${azurerm_resource_group.main.name}"
  server_name         = "${azurerm_postgresql_server.az_pgdb.name}"
  charset             = "UTF8"
  collation           = "English_United States.1252"
}