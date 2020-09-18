#
# Variables Configuration
#

variable "cluster_name" {
  default = "egov-staging"
}

variable "vpc_cidr_block" {
  default = "10.1.64.0/19"
}

variable "network_availability_zones" {
  default = ["ap-south-1b", "ap-south-1a"]
}

variable "availability_zones" {
  default = ["ap-south-1b"]
}

variable "kubernetes_version" {
  default = "1.15"
}

variable "instance_type" {
  default = "r5a.large"
}

variable "override_instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "t3a.xlarge"]
  
}

variable "number_of_worker_nodes" {
  default = "4"
}

variable "ssh_key_name" {
default = "egov-qa"
}
variable "iam_keybase_user" {
  default = "keybase:egovterraform"
}
