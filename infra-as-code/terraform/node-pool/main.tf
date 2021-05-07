provider "aws" {
  region = "ap-south-1"
}


module "eks-node-group" {
  source = "umotif-public/eks-node-group/aws"
  version = "~> 3.0.0"

  cluster_name = "${var.cluster_name}"


  node_group_name = "${var.node_group_name}"
  node_role_arn = "arn:aws:iam::680148267093:role/central-instance20210323100117412900000009"
  launch_template = {
    name = "central-instance-spot2021032310012670630000000e"
    version = "1"
  }

  subnet_ids = ["subnet-0f7580acc0543e17b"]

  desired_size = 1
  min_size     = 1
  max_size     = 1


  ec2_ssh_key = "eks-test"

  kubernetes_labels = {
    lifecycle = "OnDemand"
    name = "${var.node_group_name}"
  }

  force_update_version = true


  tags = {
    Environment = "test"
  }
}