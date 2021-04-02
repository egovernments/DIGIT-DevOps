terraform {
  backend "s3" {
    bucket = "pb-micro-uat-terraform-state"
    key = "terraform"
    region = "ap-south-1"
  }
}

module "network" {
  source             = "../modules/kubernetes/aws/network"
  vpc_cidr_block     = "${var.vpc_cidr_block}"
  cluster_name       = "${var.cluster_name}"
  availability_zones = "${var.availability_zones}"
}

module "db" {
  source                        = "../modules/db/aws"
  subnet_ids                    = "${module.network.private_subnets}"
  vpc_security_group_ids        = ["${module.network.rds_db_sg_id}"]
  availability_zone             = "${element(var.availability_zones, 0)}"
  instance_class                = "db.t3.medium"
  engine_version                = "9.6.11"
  storage_type                  = "gp2"
  storage_gb                    = "100"
  backup_retention_days         = "7"
  administrator_login           = "egovuat"
  administrator_login_password  = "${var.db_password}"
  db_name                       = "${var.cluster_name}-db"
  environment                   = "${var.cluster_name}"
}

module "eks-cluster" {
  source                        = "../modules/kubernetes/aws/eks-cluster"
  cluster_name                  = "${var.cluster_name}"
  kubernetes_version            = "${var.kubernetes_version}"
  vpc_id                        = "${module.network.vpc_id}"
//   subnets                       = "${module.network.public_subnets}"
  subnets                       = "${concat(module.network.private_subnets, module.network.public_subnets)}"
  master_nodes_security_grp_ids = ["${module.network.master_nodes_sg_id}"]
}

module "worker-nodes" {
  source                        = "../modules/kubernetes/aws/workers"
  cluster_name                  = "${var.cluster_name}"
  instance_type                 = "${var.instance_type}"
  number_of_worker_nodes        = "${var.number_of_worker_nodes}"
  ssh_key_name                  = "${var.ssh_key_name}"
  vpc_id                        = "${module.network.vpc_id}"
  eks_cluster                   = "${module.eks-cluster.eks_cluster}"
  subnets                       = "${module.network.private_subnets}"
  worker_nodes_security_grp_ids = ["${module.network.worker_nodes_sg_id}"]
}

module "es-master" {

  source = "../modules/storage/aws"
  environment = "${var.cluster_name}"
  disk_prefix = "es-master"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "2"
  
}
module "es-data-v1" {

  source = "../modules/storage/aws"
  environment = "${var.cluster_name}"
  disk_prefix = "es-data-v1"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "25"
  
}

module "es-master-infra" {

  source = "../modules/storage/aws"
  environment = "${var.cluster_name}"
  disk_prefix = "es-master-infra"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "2"
  
}
module "es-data-infra-v1" {

  source = "../modules/storage/aws"
  environment = "${var.cluster_name}"
  disk_prefix = "es-data-infra-v1"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "50"
  
}

module "zookeeper" {

  source = "../modules/storage/aws"
  environment = "${var.cluster_name}"
  disk_prefix = "zookeeper"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "5"
  
}

module "kafka" {

  source = "../modules/storage/aws"
  environment = "${var.cluster_name}"
  disk_prefix = "kafka"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "50"
  
}

module "kafka-infra" {

  source = "../modules/storage/aws"
  environment = "${var.cluster_name}"
  disk_prefix = "kafka-infra"
  availability_zones = "${var.availability_zones}"
  storage_sku = "st1"
  disk_size_gb = "500"
  
}