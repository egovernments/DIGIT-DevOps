#
# Variables Configuration
#

variable "cluster_name" {
  default = "epass-micro-prod"
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
  default = "r5a.xlarge"
}

variable "number_of_worker_nodes" {
  default = "3"
}

variable "ssh_key_name" {
  default = "epass-micro-prod"
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
      userarn  = "arn:aws:iam::218381940040:user/admin-kube-epass-micro-prod"
      username = "admin-kube-epass-micro-prod"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::218381940040:user/deployer-kube-epass-micro-prod"
      username = "deployer-kube-epass-micro-prod"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::218381940040:user/read-kube-epass-micro-prod"
      username = "read-kube-epass-micro-prod"
      groups   = ["global-readonly"]
    },    
  ]
}