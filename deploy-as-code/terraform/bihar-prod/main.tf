provider "openstack" {
  version = "~> 1.17"
}

module "es-master" {

  source = "../modules/storage/openstack"
  environment = "${var.environment}"
  disk_prefix = "es-master"
  itemCount = "3"
  disk_size_gb = "2"
  
}
module "es-data" {

  source = "../modules/storage/openstack"
  environment = "${var.environment}"
  disk_prefix = "es-data"
  itemCount = "3"
  disk_size_gb = "25"
  
}

module "es-master-infra" {

  source = "../modules/storage/openstack"
  environment = "${var.environment}"
  disk_prefix = "es-master-infra"
  itemCount = "3"
  disk_size_gb = "2"
  
}
module "es-data-infra" {

  source = "../modules/storage/openstack"
  environment = "${var.environment}"
  disk_prefix = "es-data-infra"
  itemCount = "3"
  disk_size_gb = "50"
  
}

module "zookeeper" {

  source = "../modules/storage/openstack"
  environment = "${var.environment}"
  disk_prefix = "zookeeper"
  itemCount = "3"
  disk_size_gb = "5"
  
}

module "kafka" {

  source = "../modules/storage/openstack"
  environment = "${var.environment}"
  disk_prefix = "kafka"
  itemCount = "3"
  disk_size_gb = "25"
  
}

module "kafka-infra" {

  source = "../modules/storage/openstack"
  environment = "${var.environment}"
  disk_prefix = "kafka-infra"
  itemCount = "3"
  disk_size_gb = "50"
  
}