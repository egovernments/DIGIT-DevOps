
variable "cluster_name" {}

variable "node_group_name" {}


variable "subnet" {}



variable "instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "t3a.xlarge" , "m4.xlarge"]
}

variable "kubernetes_version" {}


variable "security_groups" {}

variable "node_group_max_size" {}

variable "node_group_desired_size" {}
