provider "azurerm" {
  # whilst the `version` attribute is optional, we recommend pinning to a given version of the Provider
  version = "3.71.0"
  subscription_id  = "${var.subscription_id}"
  tenant_id        = "${var.tenant_id}" 
  client_id        = "${var.client_id}"
  client_secret    = "${var.client_secret}"
  features {}
  skip_provider_registration = true
}

terraform {
  backend "azurerm" {
      resource_group_name  = "<resource_group>"
      storage_account_name = "<storage_account_name>"
      container_name       = "<container_name>"
      key                  = "terraform.tfstate"
  }
}

module "kubernetes" {
  source = "../modules/kubernetes/azure"
  environment = "${var.environment}"
  name = "${var.environment}"
  location = "${var.location}"
  resource_group = "${var.resource_group}"
  client_id =  "${var.client_id}"
  client_secret = "${var.client_secret}"
  vm_size = "Standard_B8ms"
  ssh_public_key = "${var.environment}"
  node_count = 5

}

module "zookeeper" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  itemCount = "3"
  disk_prefix = "zookeeper"
  location = "${var.location}"
  resource_group = "${var.resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "5"
  
}

module "kafka" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  itemCount = "3"
  disk_prefix = "kafka"
  location = "${var.location}"
  resource_group = "${var.resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "50"
  
}
module "es-master" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  itemCount = "3"
  disk_prefix = "es-master"
  location = "${var.location}"
  resource_group = "${var.resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "2"
  
}
module "es-data-v1" {
  source = "../modules/storage/azure"
  environment = "${var.environment}"
  itemCount = "2"
  disk_prefix = "es-data-v1"
  location = "${var.location}"
  resource_group = "${var.resource_group}"
  storage_sku = "Premium_LRS"
  disk_size_gb = "50"
  
}

module "postgres-db" {
  source = "../modules/db/azure"
  server_name = "${var.environment}"
  resource_group = "${var.resource_group}"  
  sku_cores = "2"
  location = "${var.location}"
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
