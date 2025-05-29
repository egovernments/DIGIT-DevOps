output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnets" {
  value = module.network.private_subnet.id
}

output "public_subnets" {
  value = module.network.public_subnet.id
}

output "cluster_name" {
  value = module.kubernetes.gke_cluster.name
}

output "cluster_endpoint" {
  value = module.kubernetes.gke_cluster.endpoint
}

output "db_instance_name" {
  value = module.db.db_instance_name
}

output "db_instance_private_ip" {
  value = module.db.db_instance_private_ip
}

output "db_name" {
  value = module.db.db_name
}

output "db_username" {
  value = module.db.db_username
}

output "db_password" {
  value = module.db.db_password
  sensitive = true
}

output "sops_key" {
  value = "projects/${var.project_id}/locations/${var.region}/keyRings/${google_kms_key_ring.sops_ring.name}/cryptoKeys/${google_kms_crypto_key.sops_key.name}"
}