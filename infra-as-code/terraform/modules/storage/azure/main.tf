resource "azurerm_managed_disk" "storage" {
  count                = "${var.itemCount}"  
  name                 = "${var.disk_prefix}-${count.index}"
  location             = "${var.location}"
  resource_group_name  = "${var.resource_group}"
  storage_account_type = "${var.storage_sku}"
  create_option        = "Empty"
  disk_size_gb         = "${var.disk_size_gb}"

  tags = {
    environment = "${var.environment}"
  }
}