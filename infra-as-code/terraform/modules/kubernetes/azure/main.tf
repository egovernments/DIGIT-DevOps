resource "azurerm_kubernetes_cluster" "aks" { 
  name                = "${var.name}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group}"
  dns_prefix          = "${var.name}"

  
  default_node_pool {
    name       = "default"
    vm_size    = "${var.vm_size}"
    node_count = "${var.node_count}"
  }

  service_principal {
    client_id     = "${var.client_id}"
    client_secret = "${var.client_secret}"
  }

  network_profile {
    network_plugin = "azure"
    service_cidr  = "10.0.3.0/24"
    dns_service_ip = "10.0.3.10"
    docker_bridge_cidr = "172.17.0.1/16"
    network_policy     = "calico"
    outbound_type = "loadBalancer"
  }

  tags = {
    Environment = "${var.environment}"
  }

}

resource "azurerm_subnet_network_security_group_association" "aks" {
  subnet_id                 = "${var.subnet_id}"
  network_security_group_id = "${var.network_security_group_id}"
}