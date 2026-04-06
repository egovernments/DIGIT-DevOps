output "client_key" {
    value = "${azurerm_kubernetes_cluster.aks.kube_config.0.client_key}"
}

output "client_certificate" {
    value = "${azurerm_kubernetes_cluster.aks.kube_config.0.client_certificate}"
}

output "cluster_ca_certificate" {
    value = "${azurerm_kubernetes_cluster.aks.kube_config.0.cluster_ca_certificate}"
}

output "cluster_username" {
    value = "${azurerm_kubernetes_cluster.aks.kube_config.0.username}"
}

output "cluster_password" {
    value = "${azurerm_kubernetes_cluster.aks.kube_config.0.password}"
}

output "kube_config" {
    value = "${azurerm_kubernetes_cluster.aks.kube_config_raw}"
}

output "host" {
    value = "${azurerm_kubernetes_cluster.aks.kube_config.0.host}"
}

output "node_resource_group"{
    value = "${azurerm_kubernetes_cluster.aks.node_resource_group}"
}

output "aks_principal_id" {
    description = "The system-assigned managed identity principal ID of the AKS cluster"
    value       = "${azurerm_kubernetes_cluster.aks.identity[0].principal_id}"
}