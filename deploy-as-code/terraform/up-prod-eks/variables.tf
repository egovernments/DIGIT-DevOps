#
# Variables Configuration
#

variable "cluster_name" {
  default = "up-prod"
}

variable "vpc_cidr_block" {
  default = "192.168.0.0/16"
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
  default = "t3a.xlarge"
}

variable "override_instance_types" {
  default = ["r5a.large", "r5ad.large", "t3a.xlarge", "m4.xlarge"]
  
}

variable "number_of_worker_nodes" {
  default = "3"
}

variable "ssh_key_name" {
  default = "up-prod"
}

variable "db_password" {}

