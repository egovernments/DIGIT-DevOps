variable "db_instance_name" {}
variable "db_cpu" {}
variable "db_memory_mb" {}
variable "db_disk_size_gb" {}
variable "db_max_connections" {}
variable "region" {}
variable "vpc_id" {}
variable "db_name" {}
variable "db_username" {}
variable "db_password" {}
variable db_charset {
  default = "UTF8"
}
variable db_collation {
  default = "en_US.UTF8"
}
