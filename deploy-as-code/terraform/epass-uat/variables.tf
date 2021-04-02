#
# Variables Configuration
#

variable "cluster_name" {
  default = "epass-uat"
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
  default = "r5a.large"
}

variable "number_of_worker_nodes" {
  default = "4"
}

variable "ssh_key_name" {
  default = "epass-uat"
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
      userarn  = "arn:aws:iam::218381940040:user/admin-kube-epass-uat"
      username = "admin-kube-epass-uat"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::218381940040:user/deployer-kube-epass-uat"
      username = "deployer-kube-epass-uat"
      groups   = ["system:masters"]
    },
    {
      userarn  = "arn:aws:iam::218381940040:user/read-kube-epass-uat"
      username = "read-kube-epass-uat"
      groups   = ["global-readonly"]
    },    
  ]
}