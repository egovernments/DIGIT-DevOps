#
# Variables Configuration
#

variable "cluster_name" {
  default = "egov-portal"
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
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
  default = "t2.large"
}

variable "override_instance_types" {
  default = ["t2.large"]
  
}

variable "number_of_worker_nodes" {
  default = "1"
}

variable "ssh_key_name" {
default = "egov-dev"
}
variable "iam_keybase_user" {
  default = "keybase:egovterraform"
}
