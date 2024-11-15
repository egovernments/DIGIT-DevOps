output "node_group_id" {
  description = "Outputs of node group"
  value       = aws_eks_node_group.ng.id
}