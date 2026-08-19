variable "region" {}
variable "vpc_name" {}
variable "public_subnet_name" {}
variable "public_subnet_cidr" {}
variable "private_subnet_name" {}
variable "private_subnet_cidr" {}
variable "tags" {}
variable "project_id" {}
variable "force_peering_cleanup" {}
variable "flow_logs" {
  default = false
}
variable "flow_logs_sampling" {
  default = 0.5
}
variable "flow_logs_metadata" {
  default = "INCLUDE_ALL_METADATA"
}