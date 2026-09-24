resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version

  # OIDC issuer + Workload Identity. Enabled out-of-band via `az aks update` so
  # the ArgoCD repo-server can decrypt Azure Key Vault-backed SOPS files. Pinned
  # here so Terraform does not revert it back to the provider default (false).
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

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

    # Pinned to the live AKS defaults so Terraform does not churn this block to
    # null on every plan (azurerm re-applies a 10% surge default regardless).
    upgrade_settings {
      max_surge = "10%"
    }
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

  # Pinned to live so Terraform does not churn this block to null (see systempool).
  upgrade_settings {
    max_surge = "10%"
  }

  # The scheduling runbook changes node_count out-of-band (0 at night / desired in
  # the morning), so ignore it here to stop Terraform fighting the schedule.
  lifecycle {
    ignore_changes = [node_count]
  }

  tags = {
    Environment = var.environment
  }
}

# Dedicated USER node pool for Jenkins. Tainted dedicated=egov-jenkins:NoSchedule
# and labelled dedicated=egov-jenkins so only pods that tolerate the taint and
# select the label schedule here -- the same key/value/effect as the egov-jenkins
# nodegroup on EKS unified-dev. Created only when jenkins_node_count > 0.
resource "azurerm_kubernetes_cluster_node_pool" "jenkins" {
  count                 = var.jenkins_node_count > 0 ? 1 : 0
  name                  = "jenkins"
  kubernetes_cluster_id = azurerm_kubernetes_cluster.aks.id
  mode                  = "User"
  vm_size               = var.jenkins_vm_size
  node_count            = var.jenkins_node_count
  max_pods              = 100
  vnet_subnet_id        = var.vnet_subnet_id
  os_disk_size_gb       = var.os_disk_size_gb
  orchestrator_version  = var.kubernetes_version

  node_labels = {
    dedicated = "egov-jenkins"
  }

  node_taints = [
    "dedicated=egov-jenkins:NoSchedule",
  ]

  upgrade_settings {
    max_surge = "10%"
  }

  tags = {
    Environment = var.environment
  }
}
