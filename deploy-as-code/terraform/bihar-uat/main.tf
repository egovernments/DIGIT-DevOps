provider "azurerm" {
  # whilst the `version` attribute is optional, we recommend pinning to a given version of the Provider
  version = "=1.28.0"
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
  name = "bihar-uat"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${azurerm_resource_group.resource_group.name}"
  nodes = "5"
  client_id = "dc5e5e16-0853-4706-a3be-c45fae116f37"
  client_secret = "qOoPmOuZp80/9j.h:NQcJ-TFf9Y6ps8Z"
}

module "zookeeper" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  count = "3"
  disk_prefix = "zookeeper"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${module.kubernetes.node_resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "5"
  
}

module "kafka" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  count = "3"
  disk_prefix = "kafka"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${module.kubernetes.node_resource_group}"
  storage_sku = "Standard_LRS"
  disk_size_gb = "50"
  
}
module "es-master" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  count = "3"
  disk_prefix = "es-master"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${module.kubernetes.node_resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "2"
  
}
module "es-data-v1" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  count = "2"
  disk_prefix = "es-data-v1"
  location = "${azurerm_resource_group.resource_group.location}"
  resource_group = "${module.kubernetes.node_resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "50"
  
}

module "postgres-db" {
  source = "../modules/db/azure"
  server_name = "bihar-uat-db"
  resource_group = "${module.kubernetes.node_resource_group}"  
  sku_cores = "2"
  location = "${azurerm_resource_group.resource_group.location}"
  sku_tier = "Basic"
  storage_mb = "51200"
  backup_retention_days = "7"
  administrator_login = "biharuat"
  administrator_login_password = "62bQA8E2By6wcUUz"
  ssl_enforce = "Disabled"
  db_name = "bihar_uat_db"
  environment= "${var.environment}"
  
}
