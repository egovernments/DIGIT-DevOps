#
# Variables Configuration
#

variable "cluster_name" {
  default = "up-dev"
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
  default = "m4.xlarge"
}

variable "override_instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "m4.xlarge"]
  
}

variable "number_of_worker_nodes" {
  default = "3"
}

variable "ssh_key_name" {
  default = "up-dev"
}
variable "iam_keybase_user" {
  default = "keybase:egovterraform"
}

variable "db_password" {}

