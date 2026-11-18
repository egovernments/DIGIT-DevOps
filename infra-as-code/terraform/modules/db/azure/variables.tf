variable "sku_name" {}    
variable "location" {}
variable "resource_group" {}
variable "storage_mb" {}
variable "backup_retention_days" {}
variable "administrator_login" {}
variable "administrator_password" {}
variable "environment" {}
variable "db_version" {}
variable "delegated_subnet_id" {}
variable "private_dns_zone_id" {}
variable "extensions" {
  description = "Comma-separated azure.extensions allow-list, e.g. POSTGIS,UUID-OSSP (empty = server default)"
  default     = ""
}
