variable "environment" {}
variable "disk_prefix" {}    
variable "availability_zones" {}
variable "storage_sku" {}
variable "disk_size_gb" {}

variable "storage_count" {}

variable "snapshot_id" {
    default = "${null}"
}