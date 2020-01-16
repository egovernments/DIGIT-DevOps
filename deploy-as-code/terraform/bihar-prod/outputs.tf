output "es_master_vol_ids" {
  value = "${module.es-master.vol_ids}"
}

output "es_data_vol_ids" {
  value = "${module.es-data.vol_ids}"
}

output "zookeeper_vol_ids" {
  value = "${module.zookeeper.vol_ids}"
}

output "kafka_vol_ids" {
  value = "${module.kafka.vol_ids}"
}

output "kafka_infra_vol_ids" {
  value = "${module.kafka-infra.vol_ids}"
}

output "es_master_infra_vol_ids" {
  value = "${module.es-master-infra.vol_ids}"
}

output "es_data_infra_vol_ids" {
  value = "${module.es-data-infra.vol_ids}"
}
