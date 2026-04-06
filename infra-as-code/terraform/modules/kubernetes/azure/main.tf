resource "azurerm_kubernetes_cluster" "aks" { 
  name                = "${var.name}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group}"
  dns_prefix          = "${var.name}"

  
  default_node_pool {
    name       = "defaultpool"
    node_count = "${var.node_count}"
    max_pods   = "100"
    vm_size    = "${var.vm_size}"
    vnet_subnet_id = "${var.vnet_subnet_id}"
    node_public_ip_enabled = false
    temporary_name_for_rotation = "tempnodepool"
    os_disk_size_gb = var.os_disk_size_gb
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin     = "azure"
    outbound_type      = "userAssignedNATGateway" # Use NAT Gateway
    dns_service_ip     = "10.2.0.10"
    service_cidr       = "10.2.0.0/16"
  }

  tags = {
    Environment = "${var.environment}"
  }

}