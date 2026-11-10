provider "azurerm" {
  features {}
  subscription_id = "777e3e4b-0998-4759-adc2-e7b5b19a6b28"
}

terraform {
  required_version = ">= 1.3.0"

  # Pinned to match master. The System/User node-pool split below uses
  # node_provisioning_profile, which only exists in the azurerm v5 schema.
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 5.0"
    }
  }

  backend "azurerm" {
    resource_group_name  = "digit-lts"
    storage_account_name = "tfstate16gkx"
    container_name       = "digit-lts-container"
    key                  = "terraform.tfstate"
  }
}

resource "azurerm_virtual_network" "vnet" {
  name                = "${var.resource_group}-virtual-network"
  address_space       = var.vnet_address_space
  location            = var.location
  resource_group_name = var.resource_group
}

resource "azurerm_subnet" "aks" {
  name                 = "${var.resource_group}-aks-subnet"
  resource_group_name  = var.resource_group
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = var.aks_address_prefixes
}

# Give AKS system-assigned identity permission to join the subnet
resource "azurerm_role_assignment" "aks_subnet_network_contributor" {
  principal_id         = module.kubernetes.aks_principal_id
  role_definition_name = "Network Contributor"
  scope                = azurerm_subnet.aks.id
}

# Create Public IP for Internet Gateway
resource "azurerm_public_ip" "public_ip" {
  name                = "${var.environment}-public-ip"
  resource_group_name = var.resource_group
  location            = var.location
  allocation_method   = "Static"
  sku                 = "Standard"
}

# Create NAT Gateway (optional, for private subnet internet access)
resource "azurerm_nat_gateway" "nat" {
  name                = "${var.environment}-nat-gateway"
  location            = var.location
  resource_group_name = var.resource_group
  sku_name            = "Standard"
}

resource "azurerm_nat_gateway_public_ip_association" "nat_assoc" {
  nat_gateway_id       = azurerm_nat_gateway.nat.id
  public_ip_address_id = azurerm_public_ip.public_ip.id
}

# Associate NAT with private subnet (to give it outbound access)
resource "azurerm_subnet_nat_gateway_association" "nat_private" {
  subnet_id      = azurerm_subnet.aks.id
  nat_gateway_id = azurerm_nat_gateway.nat.id
}

module "kubernetes" {
  depends_on         = [azurerm_nat_gateway_public_ip_association.nat_assoc]
  source             = "../modules/kubernetes/azure"
  environment        = var.environment
  name               = var.environment
  location           = var.location
  resource_group     = var.resource_group
  vnet_subnet_id     = azurerm_subnet.aks.id
  os_disk_size_gb    = var.os_disk_size_gb
  kubernetes_version = var.kubernetes_version

  # Single node pool. The name MUST stay as the live cluster's existing pool
  # name -- changing it replaces the whole cluster.
  node_pool_name = var.node_pool_name
  vm_size        = var.vm_size
  node_count     = var.node_count

  # Already enabled on the live cluster; passed explicitly so a plan does not
  # turn them off. See variables.tf.
  oidc_issuer_enabled       = var.oidc_issuer_enabled
  workload_identity_enabled = var.workload_identity_enabled
  azure_rbac_enabled        = var.azure_rbac_enabled
  aad_tenant_id             = var.aad_tenant_id
  node_pool_max_surge       = var.node_pool_max_surge
}

# Azure Automation + runbook + schedules to STOP the whole cluster at night
# (21:00 IST) and START it again in the morning (08:30 IST).
#
# The cluster has a single node pool, and AKS never lets a System pool -- which
# default_node_pool always is -- scale to 0. Stopping the cluster deallocates
# every node instead, which is both possible here and cheaper.
# Created only when var.scheduling = true.
module "scheduling" {
  count  = var.scheduling ? 1 : 0
  source = "../modules/scheduling/azure"

  environment     = var.environment
  resource_group  = var.resource_group
  location        = var.location
  subscription_id = var.subscription_id

  aks_cluster_id   = module.kubernetes.aks_cluster_id
  aks_cluster_name = module.kubernetes.aks_cluster_name
  aks_subnet_id    = azurerm_subnet.aks.id

  cluster_start_time  = var.cluster_start_time
  cluster_stop_time   = var.cluster_stop_time
  schedule_timezone   = var.schedule_timezone
  schedule_utc_offset = var.schedule_utc_offset
  schedule_week_days  = var.schedule_week_days
}
