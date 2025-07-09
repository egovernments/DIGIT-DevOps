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
  identifier                    = "${var.cluster_name}-db"
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

module "eks_managed_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  name            = "${var.cluster_name}-spot"
  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
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


