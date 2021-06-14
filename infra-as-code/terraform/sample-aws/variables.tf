#
# Variables Configuration
#

## Add Cluster Name
variable "cluster_name" {
  default = "Cluster name"  
}

## Add vpc_cidr_block
variable "vpc_cidr_block" {
  default = "CIDR" 
}

variable "network_availability_zones" {
  default = ["ap-south-1b", "ap-south-1a"]
}

variable "availability_zones" {
  default = ["ap-south-1b"]
}

variable "kubernetes_version" {
  default = "1.18"
}

variable "instance_type" {
  default = "r5a.large"
}

variable "override_instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "t3a.xlarge"]
  
}

variable "number_of_worker_nodes" {
  default = "3"
}

##Add ssh key
variable "ssh_key_name" {
  default = "ssh key name"
}


variable "iam_keybase_user" {
  default = "keybase:egovterraform"
}

variable "db_password" {}

