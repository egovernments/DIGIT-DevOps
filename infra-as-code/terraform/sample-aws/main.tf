terraform {
  backend "s3" {
    key     = "terraform-setup/terraform.tfstate"
    region  = "ap-south-1"
    encrypt = true
  }
  required_providers {
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.0.2"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      version = "2.37.1"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.10.1, < 3.0.0"
    }
  }
}

locals {
  az_to_find           = var.availability_zones[0] 
  az_index_in_network  = index(var.network_availability_zones, local.az_to_find)
  ami_type_map = {
    x86_64 = "AL2023_x86_64_STANDARD"
    arm64  = "AL2023_ARM_64_STANDARD"
  }

  # Use user-specified instance_types if provided, else choose from map
  selected_instance_types = length(var.instance_types) > 0 ? var.instance_types : var.instance_types_map[var.architecture]
}

# resource "aws_iam_user" "filestore_user" {
#   name = "${var.cluster_name}-filestore-user"
#
#   tags = {
#     "KubernetesCluster" = var.cluster_name
#     "Name"              = var.cluster_name
#   }
# }
#
# resource "aws_iam_access_key" "filestore_key" {
#   user    = aws_iam_user.filestore_user.name
# }
#
# resource "kubernetes_namespace" "namespace" {
#   metadata {
#     name = var.filestore_namespace
#   }
# }
#
# resource "kubernetes_secret" "egov-filestore" {
#   depends_on  = [kubernetes_namespace.namespace]
#   metadata {
#     name      = "egov-filestore"
#     namespace = var.filestore_namespace
#   }
#
#   data = {
#     awssecretkey = aws_iam_access_key.filestore_key.secret
#     awskey       = aws_iam_access_key.filestore_key.id
#   }
#
#   type = "Opaque"
# }

# KMS key for SOPS encryption/decryption of env-secrets.yaml
resource "aws_kms_key" "sops" {
  description             = "KMS key for SOPS encryption/decryption"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  tags = {
    "KubernetesCluster" = var.cluster_name
    "Name"              = "${var.cluster_name}-sops-key"
  }
}

resource "aws_kms_alias" "sops" {
  name          = "alias/${var.cluster_name}-sops-key"
  target_key_id = aws_kms_key.sops.key_id
}

module "network" {
  source             = "../modules/kubernetes/aws/network"
  vpc_cidr_block     = "${var.vpc_cidr_block}"
  cluster_name       = "${var.cluster_name}"
  availability_zones = "${var.network_availability_zones}"
}

# PostGres DB - commented out, using postgres pod instead
# module "db" {
#   source                        = "../modules/db/aws"
#   subnet_ids                    = "${module.network.private_subnets}"
#   vpc_security_group_ids        = ["${module.network.rds_db_sg_id}"]
#   availability_zone             = "${element(var.availability_zones, 0)}"
#   instance_class                = var.db_instance_class
#   engine_version                = var.db_version
#   storage_type                  = "gp3"
#   storage_gb                    = "20"
#   backup_retention_days         = "7"
#   administrator_login           = "${var.db_username}"
#   administrator_login_password  = "${var.db_password}"
#   identifier                    = "${var.cluster_name}-db"
#   db_name                       = "${var.db_name}"
#   environment                   = "${var.cluster_name}"
# }

data "aws_caller_identity" "current" {}

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 21.0"
  name    = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id          = module.network.vpc_id
  enable_cluster_creator_admin_permissions = true
  endpoint_public_access  = true
  endpoint_private_access = true
  authentication_mode = "API_AND_CONFIG_MAP"
  create_cloudwatch_log_group = false
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
  addons = {
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
  compute_config = {
    enabled    = false
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
  version         = "~> 21.0"
  name            = "${var.cluster_name}-spot"
  ami_type        = local.ami_type_map[var.architecture]
  cluster_name    = var.cluster_name
  kubernetes_version = var.kubernetes_version
  subnet_ids      = [module.network.private_subnets[local.az_index_in_network]]
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
  instance_types = local.selected_instance_types
  ebs_optimized  = "true"
  iam_role_additional_policies = {
    CSI_DRIVER_POLICY = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
    AmazonSSMManagedInstanceCore = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
    SQS_POLICY                   = "arn:aws:iam::aws:policy/AmazonSQSFullAccess"
  }
  update_config = {
    "max_unavailable_percentage": 10
  }
  labels = {
    Environment = var.cluster_name
  }
  tags = {
    "KubernetesCluster" = var.cluster_name
    "Name"              = var.cluster_name
  }
}

module "ebs_csi_driver_irsa" {
  depends_on = [module.eks]
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
  version = "~> 5.20"
  role_name_prefix = "ebs-csi-driver-"
  attach_ebs_csi_policy = true
  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
  tags = {
    "KubernetesCluster" = var.cluster_name
    "Name"              = var.cluster_name
  }
}

# resource "aws_security_group_rule" "rds_db_ingress_workers" {
#   description              = "Allow node groups to communicate with RDS database"
#   from_port                = 5432
#   to_port                  = 5432
#   protocol                 = "tcp"
#   security_group_id        = module.network.rds_db_sg_id
#   source_security_group_id = module.eks.node_security_group_id
#   type                     = "ingress"
# }

# Fetching EKS Cluster Data after its creation
data "aws_eks_cluster" "cluster" {
  depends_on = [module.eks_managed_node_group]
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  depends_on = [module.eks_managed_node_group]
  name = var.cluster_name
}

data "aws_iam_openid_connect_provider" "oidc_arn" {
  depends_on = [module.eks_managed_node_group]
  url = data.aws_eks_cluster.cluster.identity.0.oidc.0.issuer
}

resource "aws_eks_addon" "kube_proxy" {
  depends_on = [module.eks_managed_node_group]
  cluster_name      = var.cluster_name
  addon_name        = "kube-proxy"
  resolve_conflicts_on_create = "OVERWRITE"
}
resource "aws_eks_addon" "core_dns" {
  depends_on = [module.eks_managed_node_group]
  cluster_name      = var.cluster_name
  addon_name        = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
}
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  depends_on = [module.eks_managed_node_group]
  cluster_name      = var.cluster_name
  addon_name        = "aws-ebs-csi-driver"
  service_account_role_arn = module.ebs_csi_driver_irsa.iam_role_arn
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"
}

resource "aws_eks_addon" "eks-pod-identity-agent" {
  count = var.enable_karpenter ? 1 : 0
  depends_on = [module.eks_managed_node_group]
  cluster_name      = var.cluster_name
  addon_name        = "eks-pod-identity-agent"
  resolve_conflicts_on_create = "OVERWRITE"
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }
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
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
      command     = "aws"
    }
  }
}

provider "kubectl" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name]
    command     = "aws"
  }              
}

resource "aws_iam_role_policy" "karpenter_policy" {
  count = var.enable_karpenter ? 1 : 0
  depends_on = [module.eks_managed_node_group]
  name   = "karpenter-policy"
  role   = module.eks_managed_node_group.iam_role_name
  policy = jsonencode({
    "Version": "2012-10-17",
    "Statement": [
      {
        "Effect": "Allow",
        "Action": [
          "ec2:DescribeSpotPriceHistory",
          "pricing:GetProducts",
          "ec2:DescribeInstanceTypeOfferings",
          "iam:CreateInstanceProfile",
          "iam:AddRoleToInstanceProfile",
          "ec2:DescribeImages",
          "iam:PassRole",
          "ec2:DescribeLaunchTemplates",
          "ec2:CreateLaunchTemplate",
          "iam:GetInstanceProfile",
          "iam:TagInstanceProfile",
          "ec2:CreateTags",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:TerminateInstances",
          "iam:RemoveRoleFromInstanceProfile",
          "iam:DeleteInstanceProfile"
        ],
        "Resource": "*"
      }
    ]
  })
}

module "karpenter" {
  count = var.enable_karpenter ? 1 : 0
  source = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "21.3.1"
  cluster_name = module.eks.cluster_name

  create_node_iam_role = false
  node_iam_role_arn    = module.eks_managed_node_group.iam_role_arn

  # Since the node group role will already have an access entry
  create_access_entry = false

  tags = {
    Environment = var.cluster_name
    Terraform   = "true"
    "KubernetesCluster" = var.cluster_name
  }
}

resource "helm_release" "karpenter-crd" {
  count = var.enable_karpenter ? 1 : 0
  namespace           = "kube-system"
  name                = "karpenter-crd"
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter-crd"
  version             = "1.8.1"
  wait                = true
  values = []
}

resource "helm_release" "karpenter" {
  count = var.enable_karpenter ? 1 : 0
  depends_on = [ helm_release.karpenter-crd ]
  namespace           = "kube-system"
  name                = "karpenter"
  repository          = "oci://public.ecr.aws/karpenter"
  chart               = "karpenter"
  version             = "1.8.1"
  wait                = false
  skip_crds           = true

  values = [
    <<-EOT
    logLevel: info
    serviceAccount:
      name: ${var.enable_karpenter ? module.karpenter[0].service_account : ""}
    settings:
      clusterName: ${module.eks.cluster_name}
      clusterEndpoint: ${module.eks.cluster_endpoint}
      interruptionQueue: ${var.enable_karpenter ? module.karpenter[0].queue_name : ""}
    EOT
  ]
}

resource "kubectl_manifest" "karpenter_node_class" {
  count = var.enable_karpenter ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: karpenter.k8s.aws/v1
    kind: EC2NodeClass
    metadata:
      name: default
    spec:
      amiFamily: Bottlerocket
      amiSelectorTerms:
      - id: ami-0b6753867a45581f3
      role: ${module.eks_managed_node_group.iam_role_name}
      subnetSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      securityGroupSelectorTerms:
        - tags:
            karpenter.sh/discovery: ${module.eks.cluster_name}
      tags:
        karpenter.sh/discovery: ${module.eks.cluster_name}
    status:
  amis:
  - id: var.ami_id.id
    name: var.ami_id.name
    requirements:
    - key: kubernetes.io/arch
      operator: In
      values:
      - amd64
  YAML

  depends_on = [
    helm_release.karpenter
  ]
}

resource "kubectl_manifest" "karpenter_node_pool" {
  count = var.enable_karpenter ? 1 : 0
  yaml_body = <<-YAML
    apiVersion: karpenter.sh/v1
    kind: NodePool
    metadata:
      name: default
    spec:
      template:
        spec:
          nodeClassRef:
            name: default
            group: karpenter.k8s.aws  # Updated since only a single version will be served
            kind: EC2NodeClass
          requirements:
            - key: "karpenter.k8s.aws/instance-category"
              operator: In
              values: ["r", "m"]
            - key: "karpenter.k8s.aws/instance-family"
              operator: In
              values: ["m5", "r5ad"]
            - key: "node.kubernetes.io/instance-type"
              operator: Exists
              values: ["m5ad.xlarge", "r5ad.xlarge"]
            - key: "karpenter.k8s.aws/instance-cpu"
              operator: In
              values: ["2", "4"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["amd64"]
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["spot", "on-demand"]
            - key: "karpenter.k8s.aws/instance-generation"
              operator: Gt
              values: ["2"]
      disruption:
        consolidationPolicy: WhenEmptyOrUnderutilized
        consolidateAfter: 1m
        budgets:
        - nodes: "80%"
          reasons: 
          - "Empty"
          - "Drifted"
        - nodes: "80%"
          reasons: 
          - "Underutilized"
  YAML
  depends_on = [
    kubectl_manifest.karpenter_node_class
  ]
}

module "eks-cluster-autoscaler" {
  count = var.enable_ClusterAutoscaler ? 1 : 0
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
