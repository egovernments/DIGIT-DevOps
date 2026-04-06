resource "aws_iam_role" "ec2_iam" {
  name = "${var.node_group_name}-ec2-iam"

  assume_role_policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
POLICY
}

resource "aws_iam_role_policy_attachment" "worker_nodes_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = "${aws_iam_role.ec2_iam.name}"
}

resource "aws_iam_role_policy_attachment" "worker_nodes_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = "${aws_iam_role.ec2_iam.name}"
}

resource "aws_iam_role_policy_attachment" "worker_nodes_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = "${aws_iam_role.ec2_iam.name}"
}

data "aws_ami" "eks_worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.kubernetes_version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}

resource "aws_launch_template" "launch_template" {
  name              = "template-${var.node_group_name}"
  image_id          = "${data.aws_ami.eks_worker.id}"
  ebs_optimized     = true

  network_interfaces {
    security_groups = var.security_groups
  }

  block_device_mappings {
    device_name = "/dev/xvda"

    ebs {
      volume_size = 50
      volume_type = "gp2"
    }
  }

  user_data = base64encode(<<-EOF
MIME-Version: 1.0
Content-Type: multipart/mixed; boundary="==MYBOUNDARY=="
--==MYBOUNDARY==
Content-Type: text/x-shellscript; charset="us-ascii"
#!/bin/bash
/etc/eks/bootstrap.sh "${var.cluster_name}"
--==MYBOUNDARY==--\
  EOF
  )  
}

resource "aws_eks_node_group" "ng" {

  cluster_name       = "${var.cluster_name}"
  node_group_name    = "${var.node_group_name}"
  instance_types     = "${var.instance_types}"
  node_role_arn      = "${aws_iam_role.ec2_iam.arn}"
  subnet_ids         = "${var.subnet}"
  capacity_type      = "SPOT"  
  
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
    desired_size = "${var.node_group_desired_size}"
    min_size     = 1
    max_size     = "${var.node_group_max_size}"
  }
  

  force_update_version = true
  
  launch_template {
            id   = "${aws_launch_template.launch_template.id}"
            version = "$Latest"
        }

  tags = {
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
     KubernetesCluster = "${var.cluster_name}"
     Environment = "${var.node_group_name}"
     Name = "${var.node_group_name}"
  }

  depends_on = [
    aws_iam_role_policy_attachment.worker_nodes_AmazonEKSWorkerNodePolicy,
    aws_iam_role_policy_attachment.worker_nodes_AmazonEKS_CNI_Policy,
    aws_iam_role_policy_attachment.worker_nodes_AmazonEC2ContainerRegistryReadOnly,
  ]
}

  