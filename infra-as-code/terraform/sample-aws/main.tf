terraform {
  backend "s3" {
    bucket = "digit-sandbox-terraform-bucket"
    key    = "terraform-setup/terraform.tfstate"
    region = "ap-south-1"
    # The below line is optional depending on whether you are using DynamoDB for state locking and consistency
    dynamodb_table = "digit-sandbox-terraform-bucket"
    # The below line is optional if your S3 bucket is encrypted
    encrypt = true
  }
}

module "network" {
  source             = "../modules/kubernetes/aws/network"
  vpc_cidr_block     = "${var.vpc_cidr_block}"
  cluster_name       = "${var.cluster_name}"
  availability_zones = "${var.network_availability_zones}"
}

# PostGres DB
module "db" {
  source                        = "../modules/db/aws"
  subnet_ids                    = "${module.network.private_subnets}"
  vpc_security_group_ids        = ["${module.network.rds_db_sg_id}"]
  availability_zone             = "${element(var.availability_zones, 0)}"
  instance_class                = "db.t4g.medium"  ## postgres db instance type
  engine_version                = "15.12"   ## postgres version - keep current, don't downgrade
  storage_type                  = "gp3"
  storage_gb                    = "20"     ## postgres disk size
  backup_retention_days         = "7"
  administrator_login           = "${var.db_username}"
  administrator_login_password  = "${var.db_password}"
  identifier                    = "${var.cluster_name}-db"
  db_name                       = "${var.db_name}"
  environment                   = "${var.cluster_name}"
}

data "aws_caller_identity" "current" {}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  vpc_id          = module.network.vpc_id
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  authentication_mode = "API_AND_CONFIG_MAP"
  subnet_ids      = concat(module.network.private_subnets, module.network.public_subnets)
  access_entries = {
    devops = {
      kubernetes_groups = []
      principal_arn     = "${var.iam_user_arn}"

      policy_associations = {
        devops = {
          policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = {
            type = "cluster"
          }
        }
      }
    }
  }
}

module "eks_managed_node_group" {
  depends_on = [module.eks]
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  name            = "${var.cluster_name}-ng"
  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  subnet_ids = module.network.private_subnets  # Use all private subnets for better availability
  vpc_security_group_ids  = [module.eks.node_security_group_id]
  cluster_service_cidr = module.eks.cluster_service_cidr
  use_custom_launch_template = true
  
  # Block device mappings
  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 50
        volume_type           = "gp3"
        delete_on_termination = true
      }
    }
  }
  
  # Scaling configuration
  min_size     = var.min_worker_nodes
  max_size     = var.max_worker_nodes
  desired_size = var.desired_worker_nodes
  
  # Instance configuration for better stability
  instance_types = [
    "m5.xlarge",     # Most stable and widely available
    "m5d.xlarge",    # Good alternative with local storage  
    "c5.xlarge",     # Compute optimized, usually cheaper
    "r5.xlarge",     # Memory optimized
    "m5a.xlarge",    # AMD variant, often better availability
    "c5n.xlarge"     # Network optimized, good availability
  ]
  
  # Mixed capacity strategy for stability
  capacity_type  = "SPOT"
  
  # Launch template configuration
  ebs_optimized  = "true"
  enable_monitoring = "true"
  launch_template_name = "${var.cluster_name}-lt"
  
  # Update configuration for better stability
  update_config = {
    max_unavailable_percentage = 25  # More conservative than 33%
  }
  
  # Force update version to ensure compatibility
  force_update_version = true
  iam_role_additional_policies = {
    CSI_DRIVER_POLICY = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  }
  labels = {
    Environment = var.cluster_name
    NodeType = "spot"
  }
  tags = {
    "KubernetesCluster" = var.cluster_name
    "NodeType" = "spot"
  }
}

# On-Demand Node Group for critical workloads and stability
module "eks_managed_node_group_ondemand" {
  depends_on = [module.eks]
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  name            = "${var.cluster_name}-ng-ondemand"
  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  subnet_ids = module.network.private_subnets
  vpc_security_group_ids  = [module.eks.node_security_group_id]
  cluster_service_cidr = module.eks.cluster_service_cidr
  use_custom_launch_template = true
  
  # Block device mappings
  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 50
        volume_type           = "gp3"
        delete_on_termination = true
      }
    }
  }
  
  # Conservative scaling for stability
  min_size     = 1
  max_size     = 3
  desired_size = 1  # Start with 1 stable On-Demand node
  
  # Stable instance types
  instance_types = ["m5.xlarge"]  # Single, stable instance type
  
  # On-Demand for maximum stability
  capacity_type  = "ON_DEMAND"
  
  # Launch template configuration
  ebs_optimized  = "true"
  enable_monitoring = "true"
  launch_template_name = "${var.cluster_name}-ondemand-lt"
  
  # Update configuration
  update_config = {
    max_unavailable_percentage = 25
  }
  
  # Force update version to ensure compatibility
  force_update_version = true
}

resource "aws_security_group_rule" "rds_db_ingress_workers" {
  description              = "Allow node groups to communicate with RDS database"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.network.rds_db_sg_id
  source_security_group_id = module.eks.node_security_group_id
  type                     = "ingress"
}

# Fetching EKS Cluster Data after its creation
data "aws_eks_cluster" "cluster" {
  depends_on = [module.eks]
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  depends_on = [module.eks]
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

resource "kubernetes_annotations" "gp2_default" {
  annotations = {
    "storageclass.kubernetes.io/is-default-class" : "false"
  }
  api_version = "storage.k8s.io/v1"
  kind        = "StorageClass"
  metadata {
    name = "gp2"
  }

  force = true

  depends_on = [aws_eks_addon.aws_ebs_csi_driver]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name             = data.aws_eks_cluster.cluster.name
  addon_name               = "kube-proxy"
  addon_version            = "v1.31.2-eksbuild.3"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "core_dns" {
  cluster_name             = data.aws_eks_cluster.cluster.name
  addon_name               = "coredns"
  addon_version            = "v1.11.3-eksbuild.1"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name             = data.aws_eks_cluster.cluster.name
  addon_name               = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}
