
variable "cluster_name" {
  default = "egov-staging"
}

variable "node_group_name" {
  default = "egov-staging-ng"
}

variable "instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "t3a.xlarge" , "m4.xlarge"]
}

variable "cluster_version" {
  default = "1.15"
}

variable "availability_zones" {
  default = "ap-south-1a"
}
