resource "azurerm_kubernetes_cluster" "aks" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group
  dns_prefix          = var.name
  kubernetes_version  = var.kubernetes_version

  # Single node pool. The cluster is shut down overnight by stopping the whole
  # cluster (see ../../scheduling/azure), not by scaling a pool to zero -- AKS
  # never allows a System pool, which default_node_pool always is, to reach 0.
  #
  # The pool NAME is a variable on purpose. default_node_pool.name is NOT one of
  # the properties temporary_name_for_rotation can cycle, so changing it forces
  # the ENTIRE CLUSTER to be destroyed and recreated. An existing cluster must
  # keep whatever name its default pool already has.
  default_node_pool {
    name = var.node_pool_name

    # With the autoscaler on, the node count belongs to AKS. Passing null leaves
    # the attribute computed, so Terraform reads the live count instead of
    # resetting it to var.node_count on every apply. With the autoscaler off the
    # pool is sized by hand, exactly as before.
    auto_scaling_enabled = var.auto_scaling_enabled
    node_count           = var.auto_scaling_enabled ? null : var.node_count
    min_count            = var.auto_scaling_enabled ? var.min_count : null
    max_count            = var.auto_scaling_enabled ? var.max_count : null

    max_pods                    = 100
    vm_size                     = var.vm_size
    vnet_subnet_id              = var.vnet_subnet_id
    node_public_ip_enabled      = false
    temporary_name_for_rotation = "tempnodepool"
    os_disk_size_gb             = var.os_disk_size_gb
    # Without this the nodes stay on the old version while the control plane
    # moves, so the upgrade would be only half done.
    orchestrator_version = var.kubernetes_version

    # Mirrors what the live cluster already has. Leaving this block out does not
    # mean "leave it alone" -- Terraform removes it, and per the provider docs
    # unsetting drain_timeout_in_minutes once set forces a new resource.
    upgrade_settings {
      max_surge = var.node_pool_max_surge
    }
  }

  identity {
    type = "SystemAssigned"
  }

  # These mirror settings already enabled on the live cluster. They are set
  # explicitly because the provider defaults them to false/absent, so omitting
  # them makes Terraform DISABLE them on the next apply.
  oidc_issuer_enabled       = var.oidc_issuer_enabled
  workload_identity_enabled = var.workload_identity_enabled

  # AKS-managed Entra ID integration with Azure RBAC for Kubernetes authorization.
  # Dropping this block would take cluster authorization back to local accounts.
  dynamic "azure_active_directory_role_based_access_control" {
    for_each = var.aad_tenant_id == "" ? [] : [1]
    content {
      azure_rbac_enabled = var.azure_rbac_enabled
      tenant_id          = var.aad_tenant_id
    }
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
