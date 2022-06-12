provider "azurerm" {
  # whilst the `version` attribute is optional, we recommend pinning to a given version of the Provider
  version = "=3.10.0"
  subscription_id  = "b4e1aa53-c521-44e6-8a4d-5ae107916b5b"
  tenant_id        = "593ce202-d1a9-4760-ba26-ae35417c00cb" 
  client_id        = "${var.client_id}"
  client_secret    = "${var.client_secret}"
  features {}
}

resource "azurerm_resource_group" "resource_group" {
  name     = "${var.resource_group}"
  location = "${var.location}"
  tags = {
     environment = "${var.environment}"
  }
}

module "kubernetes" {
  source = "../modules/kubernetes/azure"
  environment = "${var.environment}"
  name = "${var.environment}"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${azurerm_resource_group.resource_group.name}"
  client_id =  "${var.client_id}"
  client_secret = "${var.client_secret}"
  nodes = "${var.nodes}"
  vm_size = "Standard_A8_v2"
  ssh_public_key = "${var.environment}"
}

module "zookeeper" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  itemCount = "3"
  disk_prefix = "zookeeper"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${module.kubernetes.node_resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "5"
  
}

module "kafka" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  itemCount = "3"
  disk_prefix = "kafka"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${module.kubernetes.node_resource_group}"
  storage_sku = "Standard_LRS"
  disk_size_gb = "50"
  
}
module "es-master" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  itemCount = "3"
  disk_prefix = "es-master"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${module.kubernetes.node_resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "2"
  
}
module "es-data-v1" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  itemCount = "2"
  disk_prefix = "es-data-v1"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${module.kubernetes.node_resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "50"
  
}

module "postgres-db" {
  source = "../modules/db/azure"
  server_name = "${var.environment}"
  resource_group = "${module.kubernetes.node_resource_group}"  
  sku_cores = "2"
  location = "${azurerm_resource_group.resource_group.location}"
  sku_tier = "B_Gen5_1"
  storage_mb = "51200"
  backup_retention_days = "7"
  administrator_login = "${var.db_user}"
  administrator_login_password = "${var.db_password}"
  ssl_enforce = false
  db_name = "${var.environment}"
  environment= "${var.environment}"
  db_version = "${var.db_version}"
  
}
