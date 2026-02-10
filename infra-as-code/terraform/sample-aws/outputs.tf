output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnets" {
  value = module.network.private_subnets
}

output "public_subnets" {
  value = module.network.public_subnets
}


output "cluster_endpoint" {
  description = "Endpoint for EKS control plane."
  value       = module.eks.cluster_endpoint
}

# output "db_instance_endpoint" {
#   value = module.db.db_instance_endpoint
# }
#
# output "db_instance_name" {
#   description = "The database name"
#   value       = module.db.db_instance_name
# }
#
# output "db_instance_username" {
#   description = "The master username for the database"
#   value       = module.db.db_instance_username
#   sensitive   = true
# }
#
# output "db_instance_port" {
#   description = "The database port"
#   value       = module.db.db_instance_port
# }

output "sops_kms_key_arn" {
  description = "ARN of the KMS key used for SOPS encryption/decryption"
  value       = aws_kms_key.sops.arn
}