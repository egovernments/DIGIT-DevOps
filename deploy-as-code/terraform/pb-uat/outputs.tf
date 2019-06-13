output "config_map_aws_auth" {
  value = module.worker-nodes.config_map_aws_auth
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "private_subnets" {
  value = module.network.private_subnets
}

output "public_subnets" {
  value = module.network.public_subnets
}

output "master_nodes_sg_id" {
  value = module.network.master_nodes_sg_id
}

output "worker_nodes_sg_id" {
  value = module.network.worker_nodes_sg_id
}

output "kubeconfig" {
  value = module.eks-cluster.kubeconfig
}

output "eks_cluster" {
  value = module.eks-cluster.eks_cluster
}

output "es_master_volume_ids" {
  value = "${module.es-master.volume_ids}"
}

output "es_data_volume_ids" {
  value = "${module.es-data-v1.volume_ids}"
}

output "zookeeper_volume_ids" {
  value = "${module.zookeeper.volume_ids}"
}

output "kafka_vol_by_snapshots" {
  value = "${aws_ebs_volume.vol_by_snapshots.*.id}"
}

output "kafka_vol_1c" {
  value = "${aws_ebs_volume.kafka_1c_vol}"
}

output "kafka_infra_vol_ids" {
  value = "${module.kafka-infra.volume_ids}"
}