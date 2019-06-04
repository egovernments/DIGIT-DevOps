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