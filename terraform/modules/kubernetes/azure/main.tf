resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.name}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group}"
  dns_prefix          = "${var.name}"

  agent_pool_profile {
    name            = "default"
    count           = "${var.nodes}"
    vm_size         = "Standard_B4ms"
    os_type         = "Linux"
    os_disk_size_gb = 32
  }

  service_principal {
    client_id     = "${var.client_id}"
    client_secret = "${var.client_secret}"
  }

  role_based_access_control {
    enabled = true
  }  

  tags = {
    Environment = "${var.environment}"
  }
}