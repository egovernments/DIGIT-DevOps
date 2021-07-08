
variable "cluster_name" {
  default = "egov-staging"
}

variable "node_group_name" {
  default = "egov-staging-ng"
}


variable "subnet_ids" {
  description = "A node Private Subnet ids to launch resources in"
  default = ["subnet-027b302468708a158"]
}


variable "instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "t3a.xlarge" , "m4.xlarge"]
}

variable "cluster_version" {
  default = "1.15"
}

variable "source_security_group_ids" {
  description = "set Security group for all nodes in the cluster"
  default = ["sg-09999a357c0dbe1f3"]
}

