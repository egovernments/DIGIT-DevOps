output "zookeeper_storage_ids" {
  value = "${module.zookeeper.storage_ids}"
}

output "kafka_storage_ids" {
  value = "${module.kafka.storage_ids}"
}

output "es_master_storage_ids" {
  value = "${module.es-master.storage_ids}"
}

output "es_data_v1_storage_ids" {
  value = "${module.es-data-v1.storage_ids}"
}

output "azurerm_postgresql_flexible_server" {
  value = module.postgres-db.azurerm_postgresql_flexible_server
}

output "postgresql_flexible_server_database_name" {
  value = module.postgres-db.postgresql_flexible_server_database_name
}
