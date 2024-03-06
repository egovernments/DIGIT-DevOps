#
# EKS Worker Nodes Resources
#  * IAM role allowing Kubernetes actions to access other AWS services
#  * EC2 Security Group to allow networking traffic
#  * Data source to fetch latest EKS worker AMI
#  * AutoScaling Launch Configuration to configure worker instances
#  * AutoScaling Group to launch worker instances
#

resource "aws_iam_role" "ec2_iam" {
  name = "${var.cluster_name}-ec2-iam"

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

resource "aws_iam_instance_profile" "worker_nodes" {
  name = "${var.cluster_name}"
  role = "${aws_iam_role.ec2_iam.name}"
}

data "aws_ami" "eks_worker" {
  filter {
    name   = "name"
    values = ["amazon-eks-node-${var.eks_cluster.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}


data "template_file" "user_data_hw" {
  template = <<USERDATA
#!/bin/bash
set -o xtrace
/etc/eks/bootstrap.sh --apiserver-endpoint '${var.eks_cluster.endpoint}' --b64-cluster-ca '${var.eks_cluster.certificate_authority.0.data}' '${var.cluster_name}'
USERDATA
}

resource "aws_launch_template" "launch_template" {
  name                                = "template-${var.cluster_name}"
  iam_instance_profile {
    name = "${aws_iam_instance_profile.worker_nodes.name}"
  }
  image_id                             = "${data.aws_ami.eks_worker.id}"
  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "${var.instance_type}"
  key_name                             = "${var.ssh_key_name}"
  vpc_security_group_ids               = "${var.worker_nodes_security_grp_ids}"

  user_data                            = "${base64encode(data.template_file.user_data_hw.rendered)}"
}

resource "aws_autoscaling_group" "asg" {
  vpc_zone_identifier = "${var.subnets}"

  name                = "asg-${var.cluster_name}"
  max_size            = "${var.number_of_worker_nodes}"
  min_size            = "${var.number_of_worker_nodes}"
  desired_capacity    = "${var.number_of_worker_nodes}"

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity = "${var.number_of_worker_nodes}"
      on_demand_percentage_above_base_capacity = 0
    }

    launch_template {
      launch_template_specification {
        launch_template_id = "${aws_launch_template.launch_template.id}"
        version = "$Latest"
      }

      # override {
      #   instance_type = "r5.large"
      # }   
      
      # override {
      #   instance_type = "m5.xlarge"
      # }   

      # override {
      #   instance_type = "m4.xlarge"
      # }
    }
  }

  tag {
    key                 = "Name"
    value               = "nodes-${var.cluster_name}"
    propagate_at_launch = true
  }

  tag {
    key                 = "kubernetes.io/cluster/${var.cluster_name}"
    value               = "owned"
    propagate_at_launch = true
  }

  tag {
    key                 = "KubernetesCluster"
    value               = "${var.cluster_name}"
    propagate_at_launch = true
  } 

  tag {
    key                 = "k8s.io/role/node"
    value               = 1
    propagate_at_launch = true
  }     

}
