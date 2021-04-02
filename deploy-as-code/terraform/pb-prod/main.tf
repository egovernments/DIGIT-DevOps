terraform {
  backend "s3" {
    bucket = "pb-micro-prod-terraform-state"
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

# module "db" {
#   source                        = "../modules/db/aws"
#   subnet_ids                    = "${module.network.private_subnets}"
#   vpc_security_group_ids        = ["${module.network.rds_db_sg_id}"]
#   availability_zone             = "${element(var.availability_zones, 0)}"
#   instance_class                = "db.m5.large"
#   engine_version                = "9.6.11"
#   storage_type                  = "io1"
#   storage_gb                    = "100"
#   backup_retention_days         = "7"
#   administrator_login           = "egovprod"
#   administrator_login_password  = "${var.db_password}"
#   db_name                       = "${var.cluster_name}-db"
#   environment                   = "${var.cluster_name}"
# }

module "eks-cluster" {
  source                        = "../modules/kubernetes/aws/eks-cluster"
  cluster_name                  = "${var.cluster_name}"
  kubernetes_version            = "${var.kubernetes_version}"
  vpc_id                        = "${module.network.vpc_id}"
  subnets                       = "${concat(module.network.private_subnets, module.network.public_subnets)}"
  master_nodes_security_grp_ids = ["${module.network.master_nodes_sg_id}"]
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
  disk_size_gb = "100"
  
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
  kafka_snapshot_id = ["snap-0ef37f1a7f06d3526", "snap-08eae0101d4302003", "snap-0282397034e32840a"]
  kafka_availability_zones = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

resource "aws_ebs_volume" "vol_by_snapshots" {
  count = 3

  availability_zone = "${local.kafka_availability_zones[count.index]}"
  size              = "50"
  type              = "gp2"
  snapshot_id       = "${local.kafka_snapshot_id[count.index]}"

  tags = {
    Name = "kafka-${count.index}"
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
    values = ["amazon-eks-node-${module.eks-cluster.eks_cluster.version}-v*"]
  }

  most_recent = true
  owners      = ["602401143452"] # Amazon EKS AMI Account ID
}


data "template_file" "user_data_hw_gp" {
  template = <<USERDATA
#!/bin/bash
set -o xtrace
 
/etc/eks/bootstrap.sh '${var.cluster_name}' \
    --apiserver-endpoint '${module.eks-cluster.eks_cluster.endpoint}' \
    --b64-cluster-ca '${module.eks-cluster.eks_cluster.certificate_authority.0.data}' \
    --kubelet-extra-args \
        "--node-labels=cluster='${var.cluster_name}',nodegroup=balanced,workload=generalpurpose \
        --kube-reserved cpu=250m,memory=1Gi,ephemeral-storage=1Gi \
        --system-reserved cpu=250m,memory=0.2Gi,ephemeral-storage=1Gi \
        --eviction-hard memory.available<500Mi,nodefs.available<10%"  
USERDATA
}

resource "aws_launch_template" "launch_template_gp" {
  name                                = "template-${var.cluster_name}-gp"
  iam_instance_profile {
    name = "${aws_iam_instance_profile.worker_nodes.name}"
  }
  image_id                             = "${data.aws_ami.eks_worker.id}"
  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "m5.xlarge"
  key_name                             = "${var.ssh_key_name}"
  vpc_security_group_ids               = ["${module.network.worker_nodes_sg_id}"]

  user_data                            = "${base64encode(data.template_file.user_data_hw_gp.rendered)}"
}

resource "aws_autoscaling_group" "asg_gp" {
  vpc_zone_identifier = "${module.network.private_subnets}"

  name                = "asg-${var.cluster_name}-gp"
  max_size            = "3"
  min_size            = "3"
  desired_capacity    = "3"

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity = "3"
      on_demand_percentage_above_base_capacity = 0
    }

    launch_template {
      launch_template_specification {
        launch_template_id = "${aws_launch_template.launch_template_gp.id}"
        version = "$Latest"
      }

      override {
        instance_type = "m5.xlarge"
      }   
      
      override {
        instance_type = "m4.xlarge"
      }   

      override {
        instance_type = "c5.xlarge"
      }
    }
  }

  tag {
    key                 = "Name"
    value               = "nodes-${var.cluster_name}-gp"
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


data "template_file" "user_data_hw_mem" {
  template = <<USERDATA
#!/bin/bash
set -o xtrace
 
/etc/eks/bootstrap.sh '${var.cluster_name}' \
    --apiserver-endpoint '${module.eks-cluster.eks_cluster.endpoint}' \
    --b64-cluster-ca '${module.eks-cluster.eks_cluster.certificate_authority.0.data}' \
    --kubelet-extra-args \
        "--node-labels=cluster='${var.cluster_name}',nodegroup=memory,workload=memoryintensive \
        --kube-reserved cpu=250m,memory=1Gi,ephemeral-storage=1Gi \
        --system-reserved cpu=250m,memory=0.2Gi,ephemeral-storage=1Gi \
        --eviction-hard memory.available<500Mi,nodefs.available<10%"  
USERDATA
}

resource "aws_launch_template" "launch_template_mem" {
  name                                = "template-${var.cluster_name}-mem"
  iam_instance_profile {
    name = "${aws_iam_instance_profile.worker_nodes.name}"
  }
  image_id                             = "${data.aws_ami.eks_worker.id}"
  ebs_optimized                        = true
  instance_initiated_shutdown_behavior = "terminate"
  instance_type                        = "r5.xlarge"
  key_name                             = "${var.ssh_key_name}"
  vpc_security_group_ids               = ["${module.network.worker_nodes_sg_id}"]

  user_data                            = "${base64encode(data.template_file.user_data_hw_mem.rendered)}"
}

resource "aws_autoscaling_group" "asg_mem" {
  vpc_zone_identifier = "${module.network.private_subnets}"

  name                = "asg-${var.cluster_name}-mem"
  max_size            = "3"
  min_size            = "3"
  desired_capacity    = "3"

  mixed_instances_policy {
    instances_distribution {
      on_demand_base_capacity = "3"
      on_demand_percentage_above_base_capacity = 0
    }

    launch_template {
      launch_template_specification {
        launch_template_id = "${aws_launch_template.launch_template_mem.id}"
        version = "$Latest"
      }

      override {
        instance_type = "r5.xlarge"
      }   
      
      override {
        instance_type = "r4.xlarge"
      }   

      override {
        instance_type = "c5.xlarge"
      }
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

