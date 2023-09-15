resource "azurerm_subnet_network_security_group_association" "default" {
  subnet_id                 = "${var.subnet_id}"
  network_security_group_id = "${var.network_security_group_id}"
}

resource "azurerm_private_dns_zone" "default" {
  name                = "${var.resource_group}-pdz.postgres.database.azure.com"
  resource_group_name = "${var.resource_group}"
}

resource "azurerm_private_dns_zone_virtual_network_link" "default" {
  name                  = "${var.resource_group}-pdzvnetlink.com"
  private_dns_zone_name = azurerm_private_dns_zone.default.name
  virtual_network_id    = "${var.virtual_network_id}"
  resource_group_name   = "${var.resource_group}"
}

resource "azurerm_postgresql_flexible_server" "default" {
  name                   = "${var.resource_group}-server"
  resource_group_name    = "${var.resource_group}"
  location               = "${var.location}"
  version                = "${var.db_version}"
  delegated_subnet_id    = azurerm_subnet_network_security_group_association.default.id
  private_dns_zone_id    = azurerm_private_dns_zone.default.id
  administrator_login    = var.administrator_login
  administrator_password = var.administrator_password
  storage_mb             = "${var.storage_mb}"
  sku_name               = "${var.sku_tier}"
  backup_retention_days  = 7
}

resource "azurerm_postgresql_flexible_server_database" "default" {
  name      = "${var.resource_group}-db"
  server_id = azurerm_postgresql_flexible_server.default.id
  collation = "en_US.utf8"
  charset   = "UTF8"
}

resource "azurerm_postgresql_flexible_server_configuration" "example" {
  name                = "require_secure_transport"
  server_id         = azurerm_postgresql_flexible_server.default.id
  value               = "off"
}
