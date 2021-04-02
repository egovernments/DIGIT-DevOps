terraform {
  backend "s3" {
    bucket = "egov-cicd-terraform-state-store"
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

module "iam_user_deployer" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"

  name          = "${var.cluster_name}-kube-deployer"
  force_destroy = true  
  create_iam_user_login_profile = false
  create_iam_access_key         = true

  # User "egovterraform" has uploaded his public key here - https://keybase.io/egovterraform/pgp_keys.asc
  pgp_key = "${var.iam_keybase_user}"
}

module "iam_user_admin" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"

  name          = "${var.cluster_name}-kube-admin"
  force_destroy = true  
  create_iam_user_login_profile = false
  create_iam_access_key         = true

  # User "egovterraform" has uploaded his public key here - https://keybase.io/egovterraform/pgp_keys.asc
  pgp_key = "${var.iam_keybase_user}"
}

module "iam_user_user" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-user"

  name          = "${var.cluster_name}-kube-user"
  force_destroy = true  
  create_iam_user_login_profile = false
  create_iam_access_key         = true

  # User "test" has uploaded his public key here - https://keybase.io/test/pgp_keys.asc
  pgp_key = "${var.iam_keybase_user}"
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
  load_config_file       = false
  version                = "~> 1.11"
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  cluster_name    = "${var.cluster_name}"
  cluster_version = "${var.kubernetes_version}"
  subnets         = "${concat(module.network.private_subnets, module.network.public_subnets)}"

  tags = "${
    map(
      "kubernetes.io/cluster/${var.cluster_name}", "owned",
      "KubernetesCluster", "${var.cluster_name}"
    )
  }"

  vpc_id = "${module.network.vpc_id}"

  worker_groups_launch_template = [
    {
      name                    = "spot"
      subnets                 = "${slice(module.network.private_subnets, 0, length(var.availability_zones))}"
      override_instance_types = "${var.override_instance_types}"
      asg_max_size            = "${var.number_of_worker_nodes}"
      asg_desired_capacity    = "${var.number_of_worker_nodes}"
      kubelet_extra_args      = "--node-labels=node.kubernetes.io/lifecycle=spot"
      spot_allocation_strategy= "lowest-price"
      spot_max_price          = "${var.spot_max_price}"
      spot_instance_pools     = 1
      cpu_credits             = "standard"
    },
  ]
  
  map_users    = [
    {
      userarn  = "${module.iam_user_deployer.this_iam_user_arn}"
      username = "${module.iam_user_deployer.this_iam_user_name}"
      groups   = ["system:masters"]
    },
    {
      userarn  = "${module.iam_user_admin.this_iam_user_arn}"
      username = "${module.iam_user_admin.this_iam_user_name}"
      groups   = ["global-readonly", "digit-user"]
    },
    {
      userarn  = "${module.iam_user_user.this_iam_user_arn}"
      username = "${module.iam_user_user.this_iam_user_name}"
      groups   = ["global-readonly"]
    },    
  ]
}

module "jenkins" {

  source = "../modules/storage/aws"
  storage_count = 1
  environment = "${var.cluster_name}"
  disk_prefix = "jenkins-home"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "20"
  
}