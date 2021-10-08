output "node_group_id" {
  description = "Outputs of node group"
  value       = azurerm_kubernetes_cluster_node_pool.ng.id
}