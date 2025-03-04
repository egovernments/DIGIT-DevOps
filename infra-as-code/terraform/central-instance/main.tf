terraform {
  backend "s3" {
    bucket = "central-instance"
    key    = "terraform/terraform.tfstate"
    region = "ap-south-1"
    # The below line is optional depending on whether you are using DynamoDB for state locking and consistency
    dynamodb_table = "<s3-bucket-name>"
    # The below line is optional if your S3 bucket is encrypted
    encrypt = true
  }
  required_providers {
    kubectl = {
      source  = "gavinbunney/kubectl"
      version = "~> 1.14.0" 
    }
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
  engine_version                = "15.7"   ## postgres version
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
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
  tags = {
    "KubernetesCluster" = var.cluster_name
    "Name"              = var.cluster_name
  }
}

module "eks_managed_node_group" {
  depends_on = [module.eks]
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
  user_data_template_path = "user-data.yaml"
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
  depends_on = [module.eks_managed_node_group]
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  depends_on = [module.eks_managed_node_group]
  name = var.cluster_name
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
  resolve_conflicts_on_create = "OVERWRITE"
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

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
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
          "ec2:CreateTags",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:DeleteLaunchTemplate",
          "ec2:TerminateInstances"
        ],
        "Resource": "*"
      }
    ]
  })
}

module "karpenter" {
  count = var.enable_karpenter ? 1 : 0
  source = "terraform-aws-modules/eks/aws//modules/karpenter"
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
  version             = "1.0.8"
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
  version             = "1.0.8"
  wait                = false
  skip_crds           = true

  values = [
    <<-EOT
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
      amiFamily: AL2023
      amiSelectorTerms:
      - id: ami-0d1008f82aca87cb9
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
          kubelet:
            maxPods: 40
          nodeClassRef:
            name: default
            group: karpenter.k8s.aws  # Updated since only a single version will be served
            kind: EC2NodeClass
          requirements:
            - key: "karpenter.k8s.aws/instance-category"
              operator: In
              values: ["c", "m", "r", "t", "a"]
            - key: "karpenter.k8s.aws/instance-cpu"
              operator: In
              values: ["2", "4", "8", "16", "32"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["amd64"]
            - key: "karpenter.k8s.aws/instance-hypervisor"
              operator: In
              values: ["nitro"]
            - key: "karpenter.sh/capacity-type"
              operator: In
              values: ["spot"]
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
