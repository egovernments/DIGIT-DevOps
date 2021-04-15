provider "google" {
  project     = "${var.project_id}"
  region  = "${var.region}"
}

module "kubernetes" {
  source = "../modules/kubernetes/gke"
  project_id = "${var.project_id}"
  region = "${var.region}"
  gke_username = "${var.gke_username}"
  gke_password = "${var.gke_password}"
  machine_type = "${var.machine_type}"
  initial_node_count = "${var.initial_node_count}"
  min_node_count = "${var.min_node_count}"
  max_node_count = "${var.max_node_count}"
  cidr_range = "${var.cidr_range}"
}

module "zookeeper" {
  source = "../modules/storage/gke"
  environment = "${var.env_name}"
  itemCount = "3"
  disk_prefix = "zookeeper"
  disk_type = "pd-ssd"
  disk_size_gb = "5"
  region = "${var.region}"
  
}

module "kafka" {
  source = "../modules/storage/gke"
  environment = "${var.env_name}"
  itemCount = "3"
  disk_prefix = "kafka"
  disk_type = "pd-ssd"
  disk_size_gb = "50"
  region = "${var.region}"
  
}
module "es-master" {
  source = "../modules/storage/gke"
  environment = "${var.env_name}"
  itemCount = "3"
  disk_prefix = "es-master"
  disk_type = "pd-ssd"
  disk_size_gb = "2"
  region = "${var.region}"
  
}
module "es-data-v1" {
  source = "../modules/storage/gke"
  environment = "${var.env_name}"
  itemCount = "2"
  disk_prefix = "es-data-v1"
  disk_type = "pd-ssd"
  disk_size_gb = "50"
  region = "${var.region}"
  
}

module "postgres-db" {
  source = "../modules/db/gke"
  env_name = "${var.env_name}"
  region = "${var.region}"
  db_version = "POSTGRES_11"
  db_tier = "db-f1-micro"
  db_activation_policy = "ALWAYS"
  db_disk_autoresize = "true"
  db_disk_size = "10"
  db_disk_type = "PD_SSD"
  db_pricing_plan = "PER_USE"
  db_instance_access_cidr = "0.0.0.0/0"
  db_name = "sample"
  db_user_name = "admin"  
} 
