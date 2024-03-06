output "storage_ids" {
  value = "${azurerm_managed_disk.storage.*.id}"
}