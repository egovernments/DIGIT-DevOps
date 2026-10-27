output "public_ip" {
  description = "Public address of the sandbox node"
  value       = azurerm_public_ip.pip.ip_address
}

output "ssh_command" {
  description = "How the consuming team connects, using the shared private key"
  value       = "ssh -i <path-to-private-key> ${var.admin_username}@${azurerm_public_ip.pip.ip_address}"
}

output "fetch_kubeconfig" {
  description = "Pull the kubeconfig locally; the server address needs rewriting to the public IP"
  value       = "ssh -i <path-to-private-key> ${var.admin_username}@${azurerm_public_ip.pip.ip_address} 'sudo cat /etc/rancher/k3s/k3s.yaml' | sed 's|127.0.0.1|${azurerm_public_ip.pip.ip_address}|' > k3s-sandbox.kubeconfig"
}

output "vm_size" {
  value = var.vm_size
}
