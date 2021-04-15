resource "azurerm_kubernetes_cluster" "aks" {
  name                = "${var.name}"
  location            = "${var.location}"
  resource_group_name = "${var.resource_group}"
  dns_prefix          = "${var.name}"


  linux_profile {
      admin_username = "ubuntu"

      ssh_key {
          key_data = file(var.ssh_public_key)
      }
  }

  default_node_pool {
    name       = "default"
    node_count = "${var.nodes}"
    vm_size    = "${var.vm_size}"
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