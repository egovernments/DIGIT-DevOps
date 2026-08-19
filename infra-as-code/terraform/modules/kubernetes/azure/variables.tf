variable "name" {}
variable "resource_group" {}
variable "location" {}
variable "environment" {}
variable "vnet_subnet_id" {}
variable "os_disk_size_gb" {}
variable "kubernetes_version" {}

# Small always-on System node pool (default_node_pool)
variable "system_vm_size" {}
variable "system_node_count" {}

# Main User node pool that runs workloads (scaled 0 <-> desired by the schedule)
variable "main_vm_size" {}
variable "main_node_count" {}
