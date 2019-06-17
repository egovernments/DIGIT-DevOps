variable "env" {}
variable "project" {}
variable "resourcename" {}

variable "dmz_cidrs" {}
variable "location" {}
variable "az_cidr" {}
variable "ssh_public_key" {}


variable "frontend" { type = "map" }
variable "application" { type = "map" }
variable "postgresql" { type = "map" }
variable "elasticsearch" { type = "map" }