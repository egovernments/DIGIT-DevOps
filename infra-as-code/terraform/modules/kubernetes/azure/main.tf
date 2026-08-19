resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version

  # Always-on SYSTEM node pool (small: 2 vCPU / 4 GiB by default).
  # AKS requires at least one System node running at all times to host kube-system
  # pods (CoreDNS, metrics-server, etc.), so this pool is NEVER scaled to zero.
  default_node_pool {
    name                        = "systempool"
    node_count                  = var.system_node_count
    max_pods                    = 100
    vm_size                     = var.system_vm_size
    vnet_subnet_id              = var.vnet_subnet_id
    node_public_ip_enabled      = false
    temporary_name_for_rotation = "tempsyspool"
    os_disk_size_gb             = var.os_disk_size_gb
  }

  identity {
    type = "SystemAssigned"
  }

  # Required by azurerm v5. "Manual" = you manage node pools yourself
  # (no AKS Node Auto Provisioning / Karpenter), preserving current behavior.
  node_provisioning_profile {
    mode = "Manual"
  }

  network_profile {
    network_plugin = "azure"
    outbound_type  = "userAssignedNATGateway" # Use NAT Gateway
    dns_service_ip = "10.2.0.10"
    service_cidr   = "10.2.0.0/16"
  }

  tags = {
    Environment = var.environment
  }
}

# Main USER node pool (4 vCPU / 16 GiB by default) that runs the DIGIT workloads.
# This is the pool the scheduling runbook scales to 0 at night and back to the
# desired count in the morning. It MUST be a User pool so it can reach 0 nodes.
resource "azurerm_kubernetes_cluster_node_pool" "main" {
  name                  = "mainpool"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  mode                  = "User"
  vm_size               = var.main_vm_size
  node_count            = var.main_node_count
  max_pods              = 100
  vnet_subnet_id        = var.vnet_subnet_id
  os_disk_size_gb       = var.os_disk_size_gb
  orchestrator_version  = var.kubernetes_version

  # The scheduling runbook changes node_count out-of-band (0 at night / desired in
  # the morning), so ignore it here to stop Terraform fighting the schedule.
  lifecycle {
    ignore_changes = [node_count]
  }

  tags = {
    Environment = var.environment
  }
}
