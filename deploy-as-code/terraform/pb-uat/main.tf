module "network" {
  source             = "../modules/kubernetes/aws/network"
  vpc_cidr_block     = "${var.vpc_cidr_block}"
  cluster_name       = "${var.cluster_name}"
  availability_zones = "${var.availability_zones}"
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

module "zookeeper" {

  source = "../modules/storage/aws"
  environment = "${var.cluster_name}"
  disk_prefix = "zookeeper"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "5"
  
}

locals {
  kafka_snapshot_id = ["snap-0c938922c4bc10752", "snap-0e18843f0167b8b90"]
  kafka_availability_zones = ["ap-south-1a", "ap-south-1b"]
}

resource "aws_ebs_volume" "vol_by_snapshots" {
  count = 2

  availability_zone = "${local.kafka_availability_zones[count.index]}"
  size              = "50"
  type              = "gp2"
  snapshot_id       = "${local.kafka_snapshot_id[count.index]}"

  tags = {
    Name = "kafka-${count.index}"
    KubernetesCluster = "${var.cluster_name}"
  }
}

resource "aws_ebs_volume" "kafka_1c_vol" {
  availability_zone = "ap-south-1c"
  size              = "50"
  type              = "gp2"

  tags = {
    Name = "kafka-2"
    KubernetesCluster = "${var.cluster_name}"
  }
}

module "kafka-infra" {

  source = "../modules/storage/aws"
  environment = "${var.cluster_name}"
  disk_prefix = "kafka-infra"
  availability_zones = "${var.availability_zones}"
  storage_sku = "st1"
  disk_size_gb = "500"
  
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
  disk_size_gb = "30"
  
}