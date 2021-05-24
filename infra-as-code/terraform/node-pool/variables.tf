
variable "cluster_name" {
  default = "egov-qa"
}

variable "node_group_name" {
  default = "test-egov-qa-ng"
}

variable "node_role_arn" {
  description = "IAM EC2 worker node role arn that will be used by managed node group"
  default = "arn:aws:iam::680148267093:role/egov-qa20210318051125110500000009"
}

variable "subnet_ids" {
  description = "A node Private Subnet ids to launch resources in"
  default = ["subnet-098b9f7432948e4b6"]
}


variable "instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "t3a.xlarge" , "m4.xlarge"]
}

variable "ec2_ssh_key" {
  default = "egov-test"
}


variable "source_security_group_ids" {
  description = "set eks worker node security group id"
  default = ["sg-061cbd0161f705f74"]
}