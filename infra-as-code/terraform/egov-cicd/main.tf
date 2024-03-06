terraform {
  backend "s3" {
    bucket = "try-cicd-workshop-yourname"
    key = "terraform"
    region = "ap-south-1"
  }
}

module "network" {
  source             = "../modules/kubernetes/aws/network"
  vpc_cidr_block     = "${var.vpc_cidr_block}"
  cluster_name       = "${var.cluster_name}"
  availability_zones = "${var.network_availability_zones}"
}


data "aws_eks_cluster" "cluster" {
  name = "${module.eks.cluster_id}"
}

data "aws_eks_cluster_auth" "cluster" {
  name = "${module.eks.cluster_id}"
}
  
provider "kubernetes" {
  host                   = "${data.aws_eks_cluster.cluster.endpoint}"
  cluster_ca_certificate = "${base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)}"
  token                  = "${data.aws_eks_cluster_auth.cluster.token}"
  #load_config_file       = false
}
  
module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "17.24.0"
  cluster_name    = "${var.cluster_name}"
  vpc_id          = "${module.network.vpc_id}"
  cluster_version = "${var.kubernetes_version}"
  subnets         = "${concat(module.network.private_subnets, module.network.public_subnets)}"

  worker_groups = [
    {
      name                          = "spot"
      subnets                       = "${concat(slice(module.network.private_subnets, 0, length(var.availability_zones)))}"
      override_instance_types       = "${var.override_instance_types}"
      kubelet_extra_args            = "--node-labels=node.kubernetes.io/lifecycle=spot"
      additional_security_group_ids = ["${module.network.worker_nodes_sg_id}"]
      asg_max_size                  = "${var.number_of_worker_nodes}"
      asg_desired_capacity          = "${var.number_of_worker_nodes}"
      spot_allocation_strategy      = "capacity-optimized"
      spot_instance_pools           = null
    }
  ]
  tags = "${
    tomap({
      "kubernetes.io/cluster/${var.cluster_name}" = "owned",
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
 
}

module "jenkins" {

  source = "../modules/storage/aws"
  storage_count = 1
  environment = "${var.cluster_name}"
  disk_prefix = "jenkins-home"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "50"
  
}
