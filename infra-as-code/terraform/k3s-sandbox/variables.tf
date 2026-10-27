variable "subscription_id" {
  description = "Azure subscription that hosts the sandbox"
  default     = "777e3e4b-0998-4759-adc2-e7b5b19a6b28"
}

variable "resource_group" {
  description = "Existing resource group, created by ./remote-state"
  default     = "k3s-sandbox-rg"
}

variable "environment" {
  description = "Name prefix for every resource in this config"
  default     = "k3s-sandbox"
}

# 8 vCPU / 32 GiB. The 32 GiB is the requirement; the 8 vCPU matters because
# DIGIT core starts ~20 JVMs at once and a 4 vCPU box spends the first several
# minutes CPU-starved, which reads as random readiness-probe failures.
variable "vm_size" {
  description = "VM SKU"
  default     = "Standard_D8as_v5"
}

variable "os_disk_size_gb" {
  description = "OS disk size; also backs every local-path PVC"
  default     = 128
}

variable "admin_username" {
  description = "Shared login name on the VM"
  default     = "azureuser"
}

variable "ssh_public_key" {
  description = "Public half of the shared keypair. Supply via tfvars or -var; never commit the private key."
  type        = string
}

# Pinned to the 1.35 channel rather than "stable" so the sandbox matches the
# Kubernetes minor the unified QA/UAT clusters run. "stable" floats ahead (it
# was 1.36 at the time of writing) and would silently test DIGIT against a
# newer API surface than the environments this is meant to mirror.
variable "k3s_channel" {
  description = "k3s release channel passed to INSTALL_K3S_CHANNEL"
  default     = "v1.35"
}

variable "vnet_address_space" {
  description = "VNet CIDR"
  type        = list(string)
  default     = ["10.60.0.0/16"]
}

variable "subnet_address_prefixes" {
  description = "Subnet CIDR for the node"
  type        = list(string)
  default     = ["10.60.1.0/24"]
}

# These default to open because the consuming team's source addresses are not
# known when the sandbox is created. Narrow them once they are.
variable "allowed_ssh_cidrs" {
  description = "Source ranges permitted to reach SSH"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_api_cidrs" {
  description = "Source ranges permitted to reach the k3s API on 6443"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "allowed_http_cidrs" {
  description = "Source ranges permitted to reach 80/443"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}
