
variable "cluster_name" {
  default = "ifix-dev"
}

variable "node_group_name" {
  default = "test-egov-qa-ng"
}

variable "node_role_arn" {
  description = "IAM EC2 worker node role arn that will be used by managed node group"
  default = "arn:aws:iam::680148267093:role/ifix-dev20210622123436976900000009"
}

variable "subnet_ids" {
  description = "A node Private Subnet ids to launch resources in"
  default = ["subnet-05291070617444d58"]
}


variable "instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "t3a.xlarge" , "m4.xlarge"]
}

variable "cluster_version" {
  default = "1.18"
}

variable "source_security_group_ids" {
  description = "set Security group for all nodes in the cluster"
  default = ["sg-035bd2b16d1a37dba"]
}

