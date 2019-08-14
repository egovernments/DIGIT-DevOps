#
# Variables Configuration
#

variable "cluster_name" {
  default = "pb-micro-prod"
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

variable "ssh_key_name" {
  default = "pb-micro-prod"
}

