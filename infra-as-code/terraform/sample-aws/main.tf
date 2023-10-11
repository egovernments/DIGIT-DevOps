terraform {
  backend "s3" {
    bucket = <terraform_state_bucket_name>
    key    = "digit-bootcamp-setup/terraform.tfstate"
    region = "ap-south-1"
    # The below line is optional depending on whether you are using DynamoDB for state locking and consistency
    dynamodb_table = <terraform_state_bucket_name>
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
  instance_class                = "db.t3.medium"  ## postgres db instance type
  engine_version                = "11.20"   ## postgres version
  storage_type                  = "gp2"
  storage_gb                    = "10"     ## postgres disk size
  backup_retention_days         = "7"
  administrator_login           = "${var.db_username}"
  administrator_login_password  = "${var.db_password}"
  identifier                    = "${var.cluster_name}-db"
  db_name                       = "${var.db_name}"
  environment                   = "${var.cluster_name}"
  tags = "${
    tomap({
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
}

data "aws_eks_cluster" "cluster" {
  name = "${module.eks.cluster_id}"
}

data "aws_eks_cluster_auth" "cluster" {
  name = "${module.eks.cluster_id}"
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
  version         = "17.24.0"
  cluster_name    = "${var.cluster_name}"
  vpc_id          = "${module.network.vpc_id}"
  cluster_version = "${var.kubernetes_version}"
  subnets         = "${concat(module.network.private_subnets, module.network.public_subnets)}"

##By default worker groups is Configured with SPOT, As per your requirement you can below values.

  worker_groups = [
    {
      name                          = "spot"
      ami_id                        = "ami-0a82b544ef71a207d"   
      subnets                       = "${concat(slice(module.network.private_subnets, 0, length(var.availability_zones)))}"
      instance_type                 = "${var.instance_type}"
      override_instance_types       = "${var.override_instance_types}"
      kubelet_extra_args            = "--node-labels=node.kubernetes.io/lifecycle=spot"
      asg_max_size                  = "${var.number_of_worker_nodes}"
      asg_desired_capacity          = "${var.number_of_worker_nodes}"
      spot_allocation_strategy      = "capacity-optimized"
      spot_instance_pools           = null
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
  tags = "${
    map(
      "kubernetes.io/cluster/${var.cluster_name}", "owned",
      "KubernetesCluster", "${var.cluster_name}"
    )
  }"
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

resource "aws_iam_openid_connect_provider" "eks_oidc_provider" {
  client_id_list = ["sts.amazonaws.com"]
  thumbprint_list = ["${data.tls_certificate.thumb.certificates.0.sha1_fingerprint}"] # This should be empty or provide certificate thumbprints if needed
  url            = "${data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer}" # Replace with the OIDC URL from your EKS cluster details
}

resource "aws_security_group_rule" "rds_db_ingress_workers" {
  description              = "Allow worker nodes to communicate with RDS database" 
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = "${module.network.rds_db_sg_id}"
  source_security_group_id = "${module.eks.worker_security_group_id}"
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

module "es-master" {

  source = "../modules/storage/aws"
  storage_count = 3
  environment = "${var.cluster_name}"
  disk_prefix = "es-master"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "2"
  
}
module "es-data-v1" {

  source = "../modules/storage/aws"
  storage_count = 3
  environment = "${var.cluster_name}"
  disk_prefix = "es-data-v1"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "25"
  
}

module "zookeeper" {

  source = "../modules/storage/aws"
  storage_count = 3
  environment = "${var.cluster_name}"
  disk_prefix = "zookeeper"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "2"
  
}

module "kafka" {

  source = "../modules/storage/aws"
  storage_count = 3
  environment = "${var.cluster_name}"
  disk_prefix = "kafka"
  availability_zones = "${var.availability_zones}"
  storage_sku = "gp2"
  disk_size_gb = "50"
  
}
