#
# Variables Configuration
#

variable "cluster_name" {
  default = "pb-micro-qa"
}

variable "vpc_cidr_block" {
  default = "192.168.0.0/16"
}

variable "availability_zones" {
  default = ["ap-south-1a","ap-south-1b"]
}

variable "kubernetes_version" {
  default = "1.14"
}

variable "instance_type" {
  default = "t3a.xlarge"
}

variable "number_of_worker_nodes" {
  default = "3"
}

variable "ssh_key_name" {
  default = "egov-micro-pb-ssh"
}

variable "db_password" {}

