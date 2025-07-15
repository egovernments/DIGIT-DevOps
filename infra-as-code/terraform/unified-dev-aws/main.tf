terraform {
  backend "s3" {
    bucket = "unified-env-remote-state"
    key    = "terraform-setup/terraform.tfstate"
    region = "ap-south-1"
    # The below line is optional depending on whether you are using DynamoDB for state locking and consistency
    dynamodb_table = "unified-env-remote-state"
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
  engine_version                = "15.12"   ## postgres version
  storage_type                  = "gp3"
  storage_gb                    = "100"     ## postgres disk size
  backup_retention_days         = "7"
  administrator_login           = "${var.db_username}"
  administrator_login_password  = "${var.db_password}"
  identifier                    = "${var.cluster_name}-db-new"
  db_name                       = "${var.db_name}"
  environment                   = "${var.cluster_name}" 
}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
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
#  create_cluster_security_group = false
  iam_role_arn    = "arn:aws:iam::349271159511:role/unified-dev20230314045530411500000005" 
#  cluster_security_group_id       = "sg-0cb5e88c54d68f957"
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
  cluster_timeouts = {
    create = "30m"
    delete = "15m" 
    update = "60m"
  }
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
  tags = {
    "KubernetesCluster"                    = var.cluster_name
    "Name"                                 = var.cluster_name
  }
  cluster_tags = {
    "KubernetesCluster"                    = var.cluster_name
    "Name"                                 = var.cluster_name
    "AWS.SSM.AppManager.EKS.Cluster.ARN"   = "arn:aws:eks:ap-south-1:349271159511:cluster/unified-dev"
    "kubernetes.io/cluster/unified-dev"    = "owned"
  }
}

module "aws_auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.0"
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      groups = ["system:bootstrappers", "system:nodes"]
      rolearn = "arn:aws:iam::349271159511:role/unified-dev20230314050701738200000018"
      username = "system:node:{{EC2PrivateDNSName}}"
    },
    {
      groups = ["system:bootstrappers", "system:nodes"]
      rolearn = "arn:aws:iam::349271159511:role/KarpenterNodeRole-unified-dev"
      username = "system:node:{{EC2PrivateDNSName}}"
    },
    {
      groups = ["system:bootstrappers", "system:nodes"]
      rolearn = "arn:aws:iam::349271159511:role/unified-dev-spot-eks-node-group-20241213165811702400000001"
      username = "system:node:{{EC2PrivateDNSName}}"
    }
  ]

  aws_auth_users = [
    {
      groups = ["system:masters"]
      userarn = "arn:aws:iam::349271159511:user/egov-unified-dev-kube-deployer"
      username = "egov-unified-dev-kube-deployer"
    },
    {
      groups = ["global-readonly"]
      userarn = "arn:aws:iam::349271159511:user/sunbirdrc"
      username = "sunbirdrc"
    },
    {
      groups = ["system:masters"]
      userarn = "arn:aws:iam::349271159511:user/update-elastic"
      username = "update-elastic"
    },
    {
      groups = ["global-readonly", "digit-user"]
      userarn = "arn:aws:iam::349271159511:user/egov-unified-dev-kube-admin"
      username = "egov-unified-dev-kube-admin"
    },
    {
      groups = ["global-readonly"]
      userarn = "arn:aws:iam::349271159511:user/egov-unified-dev-kube-user"
      username = "egov-unified-dev-kube-user"
    } 
  ]
}

# EKS Node Group IAM Role
resource "aws_iam_role" "node_group_role" {
  name_prefix = "${var.cluster_name}-spot-eks-node-group-"

  assume_role_policy = jsonencode({
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ec2.amazonaws.com"
      }
      Sid = "EKSNodeAssumeRole"
    }]
    Version = "2012-10-17"
  })

  tags = {
    "KubernetesCluster" = var.cluster_name
    "Name"              = "${var.cluster_name}-node-group-role"
  }
}

# Required IAM policy attachments for EKS node group
resource "aws_iam_role_policy_attachment" "node_group_AmazonEKSWorkerNodePolicy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEKS_CNI_Policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_AmazonEC2ContainerRegistryReadOnly" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.node_group_role.name
}

# Additional policies
resource "aws_iam_role_policy_attachment" "node_group_AmazonSSMManagedInstanceCore" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_CSI_DRIVER_POLICY" {
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
  role       = aws_iam_role.node_group_role.name
}

resource "aws_iam_role_policy_attachment" "node_group_SQS_POLICY" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
  role       = aws_iam_role.node_group_role.name
}

# ARM64 On-Demand Node Group - Direct Resource
resource "aws_eks_node_group" "arm64_ondemand" {
  cluster_name    = var.cluster_name
  node_group_name = "${var.cluster_name}-arm64-ondemand"
  node_role_arn   = aws_iam_role.node_group_role.arn
  subnet_ids      = slice(module.network.private_subnets, 0, 1)
  
  capacity_type   = "ON_DEMAND"
  ami_type        = "AL2023_ARM_64_STANDARD"
  instance_types  = ["t4g.xlarge", "m6g.xlarge", "c6g.xlarge", "r6g.xlarge"]
  disk_size       = 20
  version         = var.kubernetes_version
  
  scaling_config {
    desired_size = 10
    max_size     = 15
    min_size     = 5
  }
  
  update_config {
    max_unavailable = 1
  }
  
  labels = {
    Environment = var.cluster_name
    Architecture = "arm64"
    CapacityType = "on-demand"
  }
  
  tags = {
    "KubernetesCluster" = var.cluster_name
    "Name"              = "${var.cluster_name}-arm64-ondemand"
  }
  
  depends_on = [
    aws_iam_role.node_group_role
  ]
}

resource "aws_security_group_rule" "rds_db_ingress_workers" {
  description              = "Allow worker nodes to communicate with RDS database" 
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.network.rds_db_sg_id
  source_security_group_id = module.eks.node_security_group_id
  type                     = "ingress"
}


module "zookeeper" {

  source = "../modules/storage/aws"
  storage_count = 3
  environment = "${var.cluster_name}"
  disk_prefix = "zookeeper"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp3"
  disk_size_gb = "10"
  
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
}

resource "kubernetes_storage_class" "ebs_csi_encrypted_gp3_storage_class" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" : "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "Immediate"
  parameters = {
    fsType    = "ext4"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}


