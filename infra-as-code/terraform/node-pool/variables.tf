
variable "cluster_name" {
  default = "magramseva-uat
}

variable "instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "t3a.xlarge" , "m4.xlarge"]
}

variable "kubernetes_version" {
  default = "1.20"
}

variable "availability_zones" {
  default = "ap-south-1a"
}
