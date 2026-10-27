output "storage_account_name" {
  description = "Feed this into the backend block of ../main.tf"
  value       = azurerm_storage_account.tfstate.name
}

output "container_name" {
  value = azurerm_storage_container.tfstate.name
}
