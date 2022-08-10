resource "azurerm_kubernetes_cluster" "aks" { 
  name                = "${var.name}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group}"
  dns_prefix          = "${var.name}"

  
  default_node_pool {
    name       = "default"
    node_count = "${var.nodes}"
    vm_size    = "${var.vm_size}"
  }


  service_principal {
    client_id     = "${var.client_id}"
    client_secret = "${var.client_secret}"
  }

  tags = {
    Environment = "${var.environment}"
  }

}