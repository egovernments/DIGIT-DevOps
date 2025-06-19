terraform {
  backend "s3" {
    bucket = "digit-lts-s3"
    key    = "digit-bootcamp-setup/terraform.tfstate"
    region = "ap-south-1"
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
#module "db" {
#  source                        = "../modules/db/aws"
#  subnet_ids                    = "${module.network.private_subnets}"
#  vpc_security_group_ids        = ["${module.network.rds_db_sg_id}"]
#  availability_zone             = "${element(var.availability_zones, 0)}"
#  instance_class                = "db.t3.medium"  ## postgres db instance type
#  engine_version                = "11.20"   ## postgres version
#  storage_type                  = "gp2"
#  storage_gb                    = "10"     ## postgres disk size
#  backup_retention_days         = "7"
#  administrator_login           = "${var.db_username}"
#  administrator_login_password  = "${var.db_password}"
#  identifier                    = "${var.cluster_name}-db"
#  db_name                       = "${var.db_name}"
#  environment                   = "${var.cluster_name}"
#}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

data "aws_caller_identity" "current" {}

data "tls_certificate" "thumb" {
  url = "${data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer}"
}

provider "kubernetes" {
  host                   = "${data.aws_eks_cluster.cluster.endpoint}"
  cluster_ca_certificate = "${base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)}"
  token                  = "${data.aws_eks_cluster_auth.cluster.token}"
}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  vpc_id          = module.network.vpc_id
  create_iam_role = false
  iam_role_arn    = "arn:aws:iam::680148267093:role/digit-lts20240125073044405800000003"
  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true
  authentication_mode = "API_AND_CONFIG_MAP"
  subnet_ids      = concat(module.network.private_subnets, module.network.public_subnets)
  node_security_group_additional_rules = {
    ingress_self_ephemeral = {
      description = "Node to node communication"
      protocol    = "-1"
      from_port   = 0
      to_port     = 0
      type        = "ingress"
      self        = true
    }
  }
  cluster_addons = {
    vpc-cni = {
      most_recent              = true
      before_compute           = true
      configuration_values = jsonencode({
        env = {
          # Reference docs https://docs.aws.amazon.com/eks/latest/userguide/cni-increase-ip-addresses.html
          ENABLE_PREFIX_DELEGATION           = "true"
        }
      })
    }
  }
  cluster_timeouts = {
    create = "30m"
    delete = "15m" 
    update = "60m"
  }
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
  tags = {
    "KubernetesCluster" = var.cluster_name
    "Name"              = var.cluster_name
  }
}

module "eks_managed_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  name            = "${var.cluster_name}-spot"
  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  ami_type        = "AL2_ARM_64"
  subnet_ids = slice(module.network.private_subnets, 0, length(var.availability_zones))
  vpc_security_group_ids  = [module.eks.node_security_group_id]
  cluster_service_cidr = module.eks.cluster_service_cidr
  use_custom_launch_template = true
  launch_template_name = "${var.cluster_name}-lt"
  block_device_mappings = {
    xvda = {
      device_name = "/dev/xvda"
      ebs = {
        volume_size           = 100
        volume_type           = "gp3"
        delete_on_termination = true
      }
    }
  }
  min_size     = var.min_worker_nodes
  max_size     = var.max_worker_nodes
  desired_size = var.desired_worker_nodes
  instance_types = var.instance_types
  capacity_type  = "SPOT"
  ebs_optimized  = "true"
  enable_monitoring = "true"
  iam_role_additional_policies = {
    CSI_DRIVER_POLICY = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    SQS_POLICY                   = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
  }
  labels = {
    Environment = var.cluster_name
  }
  tags = {
    "KubernetesCluster" = var.cluster_name
    "Name"              = var.cluster_name
  }
}

module "aws_auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.0"
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      groups = ["system:bootstrappers", "system:nodes"]
      rolearn = "arn:aws:iam::680148267093:role/digit-lts2024012507373138240000000c"
      username = "system:node:{{EC2PrivateDNSName}}"
    },
    {
      groups = ["system:bootstrappers", "system:nodes"]
      rolearn = "arn:aws:iam::680148267093:role/digit-lts-spot-eks-node-group-20250618163058341900000002"
      username = "system:node:{{EC2PrivateDNSName}}"
    }
  ]

  aws_auth_users = [
    {
      groups = ["global-readonly"]
      userarn = "arn:aws:iam::680148267093:user/Harish-bastion"
      username = "Harish-bastion"
    },
    {
      groups = ["global-readonly"]
      userarn = "arn:aws:iam::680148267093:user/digit-lts-user"
      username = "digit-lts-user"
    } 
  ]
}

resource "aws_iam_role" "eks_iam" {
  name = "${var.cluster_name}-eks"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Sid = "EKSWorkerAssumeRole"
        Effect = "Allow",
        Principal = {
          Federated = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:oidc-provider/${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}"
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${replace(data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}

resource "kubernetes_annotations" "example" {
  api_version = "v1"
  kind        = "ServiceAccount"
  metadata {
    name = "ebs-csi-controller-sa"
    namespace = "kube-system"
  }
  annotations = {
    "eks.amazonaws.com/role-arn" = "${aws_iam_role.eks_iam.arn}"
  }
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEBSCSIDriverPolicy" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = "${aws_iam_role.eks_iam.name}"
}

resource "aws_iam_role_policy_attachment" "cluster_AmazonEC2FullAccess" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2FullAccess"
  role       = "${aws_iam_role.eks_iam.name}"
}

resource "aws_security_group_rule" "rds_db_ingress_workers" {
  description              = "Allow worker nodes to communicate with RDS database" 
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = "${module.network.rds_db_sg_id}"
  source_security_group_id = module.eks.node_security_group_id
  type                     = "ingress"
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name      = data.aws_eks_cluster.cluster.name
  addon_name        = "kube-proxy"
  resolve_conflicts = "OVERWRITE"
}
resource "aws_eks_addon" "core_dns" {
  cluster_name      = data.aws_eks_cluster.cluster.name
  addon_name        = "coredns"
  resolve_conflicts = "OVERWRITE"
}
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name      = data.aws_eks_cluster.cluster.name
  addon_name        = "aws-ebs-csi-driver"
  resolve_conflicts = "OVERWRITE"
}

#module "es-master" {
#
#  source = "../modules/storage/aws"
#  storage_count = 3
# environment = "${var.cluster_name}"
#  disk_prefix = "es-master"
#  availability_zones = "${var.availability_zones}"
#  storage_sku = "gp2"
#  disk_size_gb = "2"
#  
#}
#module "es-data-v1" {
#
#  source = "../modules/storage/aws"
#  storage_count = 3
#  environment = "${var.cluster_name}"
# disk_prefix = "es-data-v1"
# availability_zones = "${var.availability_zones}"
#  storage_sku = "gp2"
#  disk_size_gb = "25"
#  
#}

#module "zookeeper" {
#
#  source = "../modules/storage/aws"
#  storage_count = 3
#  environment = "${var.cluster_name}"
#  disk_prefix = "zookeeper"
#  availability_zones = "${var.availability_zones}"
#  storage_sku = "gp2"
#  disk_size_gb = "2"
#  
#}

#module "kafka" {
#
#  source = "../modules/storage/aws"
#  storage_count = 3
#  environment = "${var.cluster_name}"
#  disk_prefix = "kafka"
# availability_zones = "${var.availability_zones}"
#  storage_sku = "gp2"
#  disk_size_gb = "50"
#  
#}
