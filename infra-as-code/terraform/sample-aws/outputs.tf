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

output "db_instance_endpoint" {
  value = module.db.db_instance_endpoint
}


output "db_instance_name" {
  description = "The database name"
  value       = module.db.db_instance_name
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = module.db.db_instance_username
  sensitive   = true
}

output "db_instance_port" {
  description = "The database port"
  value       = module.db.db_instance_port
}

output "s3_assets_bucket" {
  description = "Name of the assets bucket"
  value       = aws_s3_bucket.assets_bucket.id
}

output "s3_filestore_bucket" {
  description = "Name of the filestore bucket"
  value       = aws_s3_bucket.filestore_bucket.id
}
