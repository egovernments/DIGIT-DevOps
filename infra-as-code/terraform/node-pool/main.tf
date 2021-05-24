provider "aws" {
  region = "ap-south-1"
}

resource "aws_eks_node_group" "main" {
  cluster_name = "${var.cluster_name}"
  node_group_name = "${var.node_group_name}"
  node_role_arn = "${var.node_role_arn}"

  subnet_ids = "${var.subnet_ids}"
  ami_type = "AL2_x86_64"
  disk_size = 100
  instance_types = "${var.instance_types}"
  capacity_type = "SPOT"
  version = 1.15 

  labels = {
    lifecycle = "spot"
    Name = "${var.node_group_name}"
    Environment  = "${var.node_group_name}"
  }

  scaling_config {
    desired_size = 1
    min_size     = 1
    max_size     = 1
  }

  dynamic "remote_access" {
    for_each = var.ec2_ssh_key != null && var.ec2_ssh_key != "" ? ["true"] : []
    content {
      ec2_ssh_key               = var.ec2_ssh_key
      source_security_group_ids = var.source_security_group_ids
    }
  }

  force_update_version = true


  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
     KubernetesCluster = "${var.cluster_name}"
     Environment = "${var.node_group_name}"
     Name = "${var.node_group_name}"
  }
}
