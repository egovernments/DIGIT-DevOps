variable "subnet_ids" {}
variable "vpc_security_group_ids" {}
variable "availability_zone" {}
variable "instance_class" {}    
variable "engine_version" {}
variable "storage_type" {}
variable "storage_gb" {}
variable "backup_retention_days" {}
variable "administrator_login" {}
variable "administrator_login_password" {}
variable "db_name" {}
variable "identifier" {}
variable "environment" {}
variable "db_subnet_group_name" {
  default = "default-vpc-0f630338229cf5c1e"
}