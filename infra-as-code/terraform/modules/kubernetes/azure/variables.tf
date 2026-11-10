variable "name" {}
variable "resource_group" {}
variable "location" {}
variable "environment" {}
variable "vnet_subnet_id" {}
variable "os_disk_size_gb" {}
variable "kubernetes_version" {}

# NOTE: renaming this on an existing cluster forces a full cluster replacement.
variable "node_pool_name" {
  default = "defaultpool"
}
variable "vm_size" {}
variable "node_count" {}

# ---- Settings that already exist on the live cluster ----
# Each defaults to the provider's "off" value, so they must be passed in
# explicitly or a plan will quietly turn the feature off.

variable "oidc_issuer_enabled" {
  default = true
}

variable "workload_identity_enabled" {
  default = true
}

variable "azure_rbac_enabled" {
  default = true
}

# Empty string disables the Entra ID RBAC block entirely.
variable "aad_tenant_id" {
  default = ""
}

variable "node_pool_max_surge" {
  default = "10%"
}
