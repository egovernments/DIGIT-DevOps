terraform {
  backend "s3" {
    bucket = "unified-qa-s3-bucket"
    key    = "digit-bootcamp-setup/terraform.tfstate"
    region = "ap-south-1"
    # The below line is optional depending on whether you are using DynamoDB for state locking and consistency
    dynamodb_table = "unified-qa-s3-bucket"
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
  storage_gb                    = "50"   ## postgres disk size
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

data "aws_caller_identity" "current" {}

data "tls_certificate" "thumb" {
  url = "${data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer}"
}

data "aws_iam_openid_connect_provider" "oidc_arn" {
  url = data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}

provider "kubernetes" {
  host                   = "${data.aws_eks_cluster.cluster.endpoint}"
  cluster_ca_certificate = "${base64decode(data.aws_eks_cluster.cluster.certificate_authority.0.data)}"
  token                  = "${data.aws_eks_cluster_auth.cluster.token}"
}

##module "eks" {
  ##source          = "terraform-aws-modules/eks/aws"
  ##version         = "17.24.0"
  ##cluster_name    = "${var.cluster_name}"
  ##vpc_id          = "${module.network.vpc_id}"
  ##cluster_version = "${var.kubernetes_version}"
  ##subnets         = "${concat(module.network.private_subnets, module.network.public_subnets)}"

##By default worker groups is Configured with SPOT, As per your requirement you can below values.

  ##worker_groups_launch_template = [
    ##{
      ##name                          = "spot"
      ##ami_id                        = "ami-0e7bdce1244b942e2"   
      ##subnets                       = "${concat(slice(module.network.private_subnets, 0, length(var.availability_zones)))}"
      ##instance_type                 = "${var.instance_type}"
      ##override_instance_types       = "${var.override_instance_types}"
      ##kubelet_extra_args            = "--node-labels=node.kubernetes.io/lifecycle=spot"
      ##asg_max_size                  = "${var.number_of_worker_nodes}"
      ##asg_desired_capacity          = "${var.number_of_worker_nodes}"
      ##spot_allocation_strategy      = "capacity-optimized"
      ##spot_instance_pools           = null
      ##launch_template_name          = "${var.cluster_name}-lt"
      ##launch_template_version       = "$Latest"
    ##}
  ##]
  ##tags = "${
    ##tomap({
      ##"kubernetes.io/cluster/${var.cluster_name}" = "owned",
      ##"KubernetesCluster" = "${var.cluster_name}"
    ##})
  ##}"
  ##map_roles = [
    ##{
      ##groups = ["system:bootstrappers", "system:nodes"]
      ##rolearn = "arn:aws:iam::349271159511:role/unified-qa20230926140821779000000018"
      ##username = "system:node:{{EC2PrivateDNSName}}"
    ##},
    ##{
      ##groups = ["system:bootstrappers", "system:nodes"]
      ##rolearn = "arn:aws:iam::349271159511:role/KarpenterNodeRole-unified-qa"
      ##username = "system:node:{{EC2PrivateDNSName}}"
    ##}
  ##]
  ##map_users = [
    ##{
      ##groups = ["reader"]
      ##userarn = "arn:aws:iam::349271159511:user/unified-qa-user"
      ##username = "unified-qa-user"
    ##}
  ##]
##}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.0"
  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  vpc_id          = module.network.vpc_id
  create_iam_role = false
  iam_role_arn    = "arn:aws:iam::349271159511:role/unified-qa2023092614002160750000000f"
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
  cluster_timeouts = {
    create = "30m"
    delete = "15m" 
    update = "60m"
  }
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
  tags = {
    "KubernetesCluster"                         = var.cluster_name
    "kubernetes.io/cluster/${var.cluster_name}" = "owned"
  }
}

module "aws_auth" {
  source  = "terraform-aws-modules/eks/aws//modules/aws-auth"
  version = "~> 20.0"
  manage_aws_auth_configmap = true
  aws_auth_roles = [
    {
      groups = ["system:bootstrappers", "system:nodes"]
      rolearn = "arn:aws:iam::349271159511:role/unified-qa20230926140821779000000018"
      username = "system:node:{{EC2PrivateDNSName}}"
    },
    {
      groups = ["system:bootstrappers", "system:nodes"]
      rolearn = "arn:aws:iam::349271159511:role/KarpenterNodeRole-unified-qa"
      username = "system:node:{{EC2PrivateDNSName}}"
    },
    {
      groups = ["system:bootstrappers", "system:nodes"]
      rolearn = "arn:aws:iam::349271159511:role/unified-qa-spot-eks-node-group-20241227193343020700000001"
      username = "system:node:{{EC2PrivateDNSName}}"
    },
    {
      groups = ["system:bootstrappers", "system:nodes"]
      rolearn = "arn:aws:iam::349271159511:role/cast-unified-qa-eks-ae81901c"
      username = "system:node:{{EC2PrivateDNSName}}"
    },
    {
      groups = ["system:masters"]
      rolearn = "arn:aws:iam::349271159511:role/eks-alert-lambda-role"
      username = "eks-alert-lambda-role"
    }
  ]

  aws_auth_users = [
    {
      groups = ["reader"]
      userarn = "arn:aws:iam::349271159511:user/unified-qa-user"
      username = "unified-qa-user"
    } 
  ]
}

module "eks_managed_node_group" {
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version = "~> 20.0"
  name            = "${var.cluster_name}-spot"
  cluster_name    = var.cluster_name
  cluster_version = var.kubernetes_version
  subnet_ids = slice(module.network.private_subnets, 0, length(var.availability_zones))
  vpc_security_group_ids  = [module.eks.node_security_group_id]
  cluster_service_cidr = module.eks.cluster_service_cidr
  use_custom_launch_template = false
  # user_data_template_path = "user-data.yaml"  # Disable custom user-data for ARM64
  disk_size    = 100
  min_size     = var.min_worker_nodes
  max_size     = var.max_worker_nodes
  desired_size = var.desired_worker_nodes
  instance_types = var.instance_types
  ami_type      = "AL2_ARM_64"
  capacity_type  = "ON_DEMAND"
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

##resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  ##client_id_list = ["sts.amazonaws.com"]
  ##thumbprint_list = ["${data.tls_certificate.thumb.certificates.0.sha1_fingerprint}"] # This should be empty or provide certificate thumbprints if needed
  ##url            = "${data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer}" # Replace with the OIDC URL from your EKS cluster details
##}

resource "aws_security_group_rule" "rds_db_ingress_workers" {
  description              = "Allow worker nodes to communicate with RDS database" 
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = module.network.rds_db_sg_id
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
  volume_binding_mode    = "WaitForFirstConsumer"
  parameters = {
    fsType    = "ext4"
    encrypted = true
    type      = "gp3"
  }

  depends_on = [kubernetes_annotations.gp2_default]
}

provider "helm" {
  kubernetes  {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

module "eks-cluster-autoscaler" {
  source  = "lablabs/eks-cluster-autoscaler/aws"
  version = "3.1.0"
  cluster_name = var.cluster_name
  cluster_identity_oidc_issuer = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
  cluster_identity_oidc_issuer_arn = data.aws_iam_openid_connect_provider.oidc_arn.arn
  irsa_role_name = var.cluster_name
  namespace = "autoscaler"
  service_account_name = "cluster-autoscaler"
  service_account_namespace = "autoscaler"
  values = yamlencode({
    extraArgs = {
      logtostderr: true
      stderrthreshold: "info"
      v: 4
      scale-down-utilization-threshold: 0.6
    }
  })
}

