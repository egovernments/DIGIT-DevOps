#
# Variables Configuration
#

variable "cluster_name" {
  default = "cental-instance-test"
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

variable "node_pool_zone" {
 default = ["ap-south-1a"] 
}

variable "kubernetes_version" {
  default = "1.20"
}

variable "instance_type" {
  default = "m4.xlarge"
}

variable "override_instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "m4.xlarge"]
  
}

variable "number_of_worker_nodes" {
  default = "1"
}

variable "ssh_key_name" {
  default = "ifix-dev"
}

variable "db_name" {
  description = "RDS DB name. Make sure there are no hyphens or other special characters in the DB name. Else, DB creation will fail"
  default = "test_db"
}

variable "db_password" {}







