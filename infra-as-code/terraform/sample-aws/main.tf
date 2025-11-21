terraform {
  backend "s3" {
    bucket = "digit-lts-s3"
    key    = "digit-bootcamp-setup/terraform.tfstate"
    region = "ap-south-1"
    # The below line is optional if your S3 bucket is encrypted
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
  version         = "~> 21.0"
  name    = var.cluster_name
  kubernetes_version = var.kubernetes_version
  vpc_id          = module.network.vpc_id
  create_iam_role = false
  iam_role_arn    = "arn:aws:iam::680148267093:role/digit-lts20240125073044405800000003"
  endpoint_public_access  = true
  endpoint_private_access = true
  create_cloudwatch_log_group = false
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
  timeouts = {
    create = "30m"
    delete = "15m" 
    update = "60m"
  }
  access_entries = {
    readonly = {
      kubernetes_groups = ["global-readonly"]
      principal_arn     = "arn:aws:iam::680148267093:user/digit-lts-user"
      user_name         = "digit-lts-user"
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
  source = "terraform-aws-modules/eks/aws//modules/eks-managed-node-group"
  version         = "~> 21.0"
  name            = "${var.cluster_name}-spot"
  cluster_name    = var.cluster_name
  kubernetes_version = var.kubernetes_version
  ami_type        = "AL2023_ARM_64_STANDARD"
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
  update_config = {
    "max_unavailable_percentage": 10
  }
  min_size     = var.min_worker_nodes
  max_size     = var.max_worker_nodes
  desired_size = var.desired_worker_nodes
  instance_types = var.instance_types
  ebs_optimized  = "true"
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
  resolve_conflicts_on_create = "OVERWRITE"
}
resource "aws_eks_addon" "core_dns" {
  cluster_name      = data.aws_eks_cluster.cluster.name
  addon_name        = "coredns"
  resolve_conflicts_on_create = "OVERWRITE"
}
resource "aws_eks_addon" "aws_ebs_csi_driver" {
  cluster_name      = data.aws_eks_cluster.cluster.name
  addon_name        = "aws-ebs-csi-driver"
  resolve_conflicts_on_create = "OVERWRITE"
}

provider "helm" {
  kubernetes  {
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
  version         = "~> 21.0"
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
  version             = "1.5.0"
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
  version             = "1.5.0"
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
      amiFamily: AL2
      amiSelectorTerms:
      - id: ami-0431db82d7dc815dd
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
      - arm64
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
              values: ["r", "t"]
            - key: "karpenter.k8s.aws/instance-family"
              operator: In
              values: ["t4g", "r6"]
            - key: "node.kubernetes.io/instance-type"
              operator: Exists
              values: ["r6g.large", "t4g.xlarge", "t4g.2xlarge"]
            - key: "karpenter.k8s.aws/instance-cpu"
              operator: In
              values: ["2", "4", "8"]
            - key: "kubernetes.io/arch"
              operator: In
              values: ["arm64"]
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
