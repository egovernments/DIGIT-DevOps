#
# Variables Configuration
#

variable "cluster_name" {
  default = "ukd-micro-uat"
}

variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}


variable "availability_zones" {
  default = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}

variable "kubernetes_version" {
  default = "1.12"
}

variable "instance_type" {
  default = "r5.xlarge"
}

variable "number_of_worker_nodes" {
  default = "4"
}

variable "ssh_key_name" {
  default = "ukd-uat-ssh"
}