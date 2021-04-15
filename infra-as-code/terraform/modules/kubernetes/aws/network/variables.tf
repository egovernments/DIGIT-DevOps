variable "vpc_cidr_block" {
  default = "10.0.0.0/16"
}

variable "cluster_name" {
}

variable "availability_zones" {
  default = ["ap-south-1a", "ap-south-1b", "ap-south-1c"]
}