
data "oci_identity_availability_domains" "ADs" {
  compartment_id = var.tenancy_id
}

module "network" {
  source             = "../modules/kubernetes/oci/network"
  vcn_cidr           = var.vcn_cidr
  tenancy_id         = var.tenancy_id
  ClusterName        = var.ClusterName
  dns-label          = var.dns-label
}

module "oke" {
  source              = "../modules/kubernetes/oci/oke-cluster"
  tenancy_id          = var.tenancy_id
  kubernetes_version  = var.kubernetes_version
  ClusterName         = var.ClusterName
  Shape               = var.Shape
  node_pool_size      = var.node_pool_size
  availability_domain = lookup(data.oci_identity_availability_domains.ADs.availability_domains[0], "name")
  vcn_id              = module.network.vcn_id
  public_subnet_id            = module.network.public_subnet_id
  private_subnet_id            = module.network.private_subnet_id
  service_lb_subnet_ids = module.network.service_lb_subnet_ids
}

module "es-master" {
  source = "../modules/storage/oci"
  instance_count = 3
  compartment_id = var.compartment_id
  vol_name = "es-master"
  block_storage_sizes_in_gbs = 50
  ad = "ZxhC:AP-MUMBAI-1-AD-1"  
}
module "es-data-v1" {
  source = "../modules/storage/oci"
  instance_count = 3
  compartment_id = var.compartment_id
  vol_name = "es-data-v1"
  block_storage_sizes_in_gbs = 50
  ad = "ZxhC:AP-MUMBAI-1-AD-1"   
}

module "zookeeper" {
  source = "../modules/storage/oci"
  instance_count = 3
  compartment_id = var.compartment_id
  vol_name = "zookeeper"
  block_storage_sizes_in_gbs = 50
  ad = "ZxhC:AP-MUMBAI-1-AD-1"  
}

module "kafka" {
  source = "../modules/storage/oci"
  instance_count = 3
  compartment_id = var.compartment_id
  vol_name = "kafka"
  block_storage_sizes_in_gbs = 50
  ad = "ZxhC:AP-MUMBAI-1-AD-1"  
}