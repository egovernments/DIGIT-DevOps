provider "aws" {
  region = "ap-south-1"
}

resource "aws_eks_node_group" "main" {
  cluster_name = "${var.cluster_name}"
  node_group_name = "${var.node_group_name}"
  node_role_arn = "${var.node_role_arn}"

  subnet_ids = "${var.subnet_ids}"
  ami_type = "AL2_x86_64"
  disk_size = 50
  instance_types = "${var.instance_types}"
  capacity_type = "SPOT"
  version = "${var.cluster_version}"
  
  taint {
    key = "dedicated"
    value = "${var.node_group_name}"
    effect = "NO_SCHEDULE"
  }
   

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
  

  force_update_version = true


  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
     KubernetesCluster = "${var.cluster_name}"
     Environment = "${var.node_group_name}"
     Name = "${var.node_group_name}"
  }
}
