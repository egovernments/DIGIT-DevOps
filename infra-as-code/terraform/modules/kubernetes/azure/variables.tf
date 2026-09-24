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

# Dedicated User node pool for Jenkins, tainted so only Jenkins pods land on it
# (mirrors the egov-jenkins nodegroup on EKS unified-dev). Created only when
# jenkins_node_count > 0.
variable "jenkins_vm_size" {}
variable "jenkins_node_count" {}
