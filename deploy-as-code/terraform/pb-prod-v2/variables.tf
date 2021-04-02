#
# Variables Configuration
#

variable "cluster_name" {
  default = "pb-prod-v2"
}

variable "vpc_cidr_block" {
  default = "172.16.224.0/19"
}

variable "network_availability_zones" {
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "availability_zones" {
  default = ["ap-south-1a"]
}

variable "kubernetes_version" {
  default = "1.15"
}

variable "instance_type" {
  default = "r5.xlarge"
}

variable "override_instance_types" {
  default = ["r5.xlarge", "r5ad.large", "r5d.large", "r5n.xlarge"]
  
}

variable "number_of_worker_nodes" {
  default = "6"
}

variable "ssh_key_name" {
default = "pb-micro-prod"
}
variable "iam_keybase_user" {
  default = "keybase:egovterraform"
}
