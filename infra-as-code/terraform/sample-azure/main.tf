provider "azurerm" {
  subscription_id            = var.subscription_id
  tenant_id                  = var.tenant_id
  client_id                  = var.client_id
  client_secret              = var.client_secret
  features {}
}

terraform {
  backend "azurerm" {
    resource_group_name  = "digit-infra-terraform-rg"
    storage_account_name = "tfstateanaks"
    container_name       = "digit-infra-terraform-container"
    key                  = "terraform.tfstate"
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.resource_group}-virtual-network"
  address_space       = ["10.0.0.0/16"]
  location            = var.location
  resource_group_name = var.resource_group
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.resource_group}-aks-subnet"
  resource_group_name  = var.resource_group
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "postgres" {
  name                 = "${var.resource_group}-postgres-subnet"
  resource_group_name  = var.resource_group
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = ["10.0.2.0/24"]
  service_endpoints    = ["Microsoft.Storage"]

  delegation {
    name = "fs"

    service_delegation {
      name = "Microsoft.DBforPostgreSQL/flexibleServers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

resource "azurerm_private_dns_zone_virtual_network_link" "db_net_link" {
  name                  = "${var.environment}VnetZone.com"
  private_dns_zone_name = azurerm_private_dns_zone.db.name
  virtual_network_id    = azurerm_virtual_network.vnet.id
  resource_group_name   = var.resource_group
}

resource "azurerm_private_dns_zone" "db" {
  name                = "${var.environment}.postgres.database.azure.com"
  resource_group_name = var.resource_group
}

/* resource "azurerm_network_security_group" "aks_nsg" {
  name                = "aks-nsg"
  location            = var.location
  resource_group_name = var.resource_group
}

resource "azurerm_network_security_group" "db_nsg" {
  name                = "db-nsg"
  location            = var.location
  resource_group_name = var.resource_group
}

resource "azurerm_network_security_rule" "example" {
  name                        = "aks_rule1"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "80"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group
  network_security_group_name = azurerm_network_security_group.aks_nsg.name
}

resource "azurerm_network_security_rule" "example2" {
  name                        = "aks_rule2"
  priority                    = 500
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = var.resource_group
  network_security_group_name = azurerm_network_security_group.aks_nsg.name
}
*/

module "kubernetes" {
  source                    = "../modules/kubernetes/azure"
  environment               = var.environment
  name                      = var.environment
  location                  = var.location
  resource_group            = var.resource_group
  client_id                 = var.client_id
  client_secret             = var.client_secret
  vm_size                   = "Standard_D2_v2"
  node_count                = 3
  vnet_subnet_id            = azurerm_subnet.aks.id
}

module "postgres-db" {
  source                    = "../modules/db/azure"
  environment               = var.environment
  resource_group            = var.resource_group
  location                  = var.location
  sku_name                  = "B_Standard_B1ms"
  storage_mb                = "65536"
  backup_retention_days     = "7"
  administrator_login       = var.db_user
  administrator_password    = var.db_password
  db_version                = var.db_version
  delegated_subnet_id       = azurerm_subnet.postgres.id
  private_dns_zone_id       = azurerm_private_dns_zone.db.id
}