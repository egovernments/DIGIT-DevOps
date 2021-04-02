locals {
  config_map_aws_auth = <<CONFIGMAPAWSAUTH


apiVersion: v1
kind: ConfigMap
metadata:
  name: aws-auth
  namespace: kube-system
data:
  mapRoles: |
    - rolearn: ${aws_iam_role.ec2_iam.arn}
      username: system:node:{{EC2PrivateDNSName}}
      groups:
        - system:bootstrappers
        - system:nodes
CONFIGMAPAWSAUTH
}

output "config_map_aws_auth" {
  value = "${local.config_map_aws_auth}"
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

// output "kafka_infra_vol_ids" {
//   value = "${module.kafka-infra.volume_ids}"
// }

output "es_master_infra_volume_ids" {
  value = "${module.es-master-infra.volume_ids}"
}

output "es_data_infra_volume_ids" {
  value = "${module.es-data-infra-v1.volume_ids}"
}

// output "db_rds_postgres_address" {
//   value = "${module.db.rds_postgres_address}"
// }