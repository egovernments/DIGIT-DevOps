#
# Variables Configuration
#

variable "cluster_name" {
  default = "ifix-dev"
}

variable "vpc_cidr_block" {
  default = "192.172.32.0/19"
}

variable "network_availability_zones" {
  default = ["ap-south-1a", "ap-south-1b"]
}

variable "availability_zones" {
  default = ["ap-south-1a"]
}

variable "kubernetes_version" {
  default = "1.18"
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
  default = "ifix-dev"
}
variable "iam_keybase_user" {
 default = "keybase:egovterraform"
}


