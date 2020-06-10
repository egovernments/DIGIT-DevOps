#
# Variables Configuration
#

variable "cluster_name" {
  default = "egov-micro-qa"
}

variable "vpc_cidr_block" {
  default = "192.168.0.0/16"
}

variable "network_availability_zones" {
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "availability_zones" {
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "kubernetes_version" {
  default = "1.15"
}

variable "instance_type" {
  default = "r5.large"
}

variable "number_of_worker_nodes" {
  default = "4"
}

variable "ssh_key_name" {
  default = "egov-micro-qa"
}

variable "db_password" {}

variable "map_users" {
  description = "Additional IAM users to add to the aws-auth configmap."
  type = list(object({
    userarn  = string
    username = string
    groups   = list(string)
  }))

  default = [
    {
      userarn  = "arn:aws:iam::880678429748:user/admin-kube-egov-micro-qa"
      username = "admin-kube-egov-micro-qa"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::880678429748:user/deployer-kube-egov-micro-qa"
      username = "deployer-kube-egov-micro-qa"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::880678429748:user/read-kube-egov-micro-qa"
      username = "read-kube-egov-micro-qa"
      groups   = ["global-readonly"]
    },    
  ]
}