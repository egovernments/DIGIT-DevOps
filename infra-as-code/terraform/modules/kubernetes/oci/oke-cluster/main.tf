resource "oci_containerengine_cluster" "OKECluster" {
  compartment_id     = var.tenancy_id
  kubernetes_version = var.kubernetes_version
  name               = var.ClusterName
  vcn_id             = var.vcn_id

  endpoint_config {
    is_public_ip_enabled = true
    subnet_id            = var.public_subnet_id
  }

  options {
    service_lb_subnet_ids = [var.service_lb_subnet_ids]

    add_ons {
      is_kubernetes_dashboard_enabled = false
      is_tiller_enabled               = false
    }
  }
}

data "oci_containerengine_node_pool_option" "OKEClusterNodePoolOption" {
  node_pool_option_id = "all"
}

locals {
  all_sources = data.oci_containerengine_node_pool_option.OKEClusterNodePoolOption.sources
  oracle_linux_images = [for source in local.all_sources : source.image_id if length(regexall("Oracle-Linux-[0-9]*.[0-9]*-20[0-9]*",source.source_name)) > 0]
}

resource "oci_containerengine_node_pool" "OKENodePool" {
  cluster_id         = oci_containerengine_cluster.OKECluster.id
  compartment_id     = var.tenancy_id
  kubernetes_version = var.kubernetes_version
  name               = "${var.ClusterName}-ng"
  node_shape         = var.Shape

  initial_node_labels {
      key = "Environment"
      value = "${var.ClusterName}-ng"
  }
  
  node_source_details {
    image_id = local.oracle_linux_images.0
    source_type = "IMAGE"
  }

  node_shape_config {
    #ocpus = 2
    #memory_in_gbs = 50
  }

  node_config_details {
    size      = var.node_pool_size

    placement_configs {
      availability_domain = var.availability_domain
      subnet_id           = var.private_subnet_id
    }  
  }

  initial_node_labels {
    key   = "key"
    value = "value"
  }

  #ssh_public_key      = file(var.public_key_oci)
}