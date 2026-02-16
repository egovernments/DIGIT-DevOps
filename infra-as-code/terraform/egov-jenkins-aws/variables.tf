#
# Variables Configuration
#

variable "cluster_name" {
  default = "egov-jenkins"
}

variable "vpc_cidr_block" {
  default = "192.168.0.0/16"
}

variable "network_availability_zones" {
  default = ["ap-south-1b", "ap-south-1a"]
}

variable "availability_zones" {
  default = ["ap-south-1b"]
}

variable "kubernetes_version" {
  default = "1.33"
}

variable "instance_types" {
  description = "eGov recommended below instance type as a default"
  default = ["m6a.xlarge"]
}

variable "min_worker_nodes" {
  description = "eGov recommended below worker node counts as default for min nodes"
  default = "1" #REPLACE IF NEEDED
}

variable "desired_worker_nodes" {
  description = "eGov recommended below worker node counts as default for desired nodes"
  default = "2" #REPLACE IF NEEDED
}

variable "max_worker_nodes" {
  description = "eGov recommended below worker node counts as default for max nodes"
  default = "2" #REPLACE IF NEEDED
}
variable "override_instance_types" {
  default = ["t3.xlarge", "r5ad.xlarge", "r5a.xlarge", "t3a.xlarge"]
}

variable "number_of_worker_nodes" {
  default = "1"
}


variable "spot_max_price" {
  default = "0.0538"
}

variable "ssh_key_name" {
  default = "egov-jenkins"
}

variable "iam_user_arn" {
  description = "Provide the IAM user arn which you are using to create infrastructure"
  default = "arn:aws:iam::218381940040:user/admin-jenkins"
}