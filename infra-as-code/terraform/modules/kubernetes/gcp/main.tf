resource "google_container_cluster" "gke_cluster" {
  name     = var.cluster_name
  location = var.zone

  remove_default_node_pool = true
  initial_node_count       = 1

  network    = var.vpc_id
  subnetwork = var.subnet_id

  min_master_version = var.k8s_version
  deletion_protection = false
  resource_labels     = var.cluster_resource_labels

  ip_allocation_policy {}

  # Enable Workload Identity (free). Required for the node pool's
  # workload_metadata_config mode = "GKE_METADATA".
  workload_identity_config {
    workload_pool = "${var.project_id}.svc.id.goog"
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${var.cluster_name}-node-pool"
  cluster    = google_container_cluster.gke_cluster.name
  location   = var.zone

  node_config {
    machine_type = var.node_machine_type
    oauth_scopes = ["https://www.googleapis.com/auth/cloud-platform"]
    tags         = ["${var.cluster_name}-gke-node"]
    image_type        = "COS_CONTAINERD"
    disk_type         = var.node_disk_type
    boot_disk_kms_key = var.boot_disk_kms_key
    disk_size_gb = var.node_disk_size_gb
    workload_metadata_config {
      mode = "GKE_METADATA"
    }
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }

  autoscaling {
    min_node_count = var.min_node_count
    max_node_count = var.max_node_count
  }

  initial_node_count = var.desired_node_count
}

resource "google_compute_firewall" "gke_lb_ingress" {
  name    = "${var.cluster_name}-gke-lb-ingress"
  network = var.vpc_id

  allow {
    protocol = "tcp"
    ports    = ["80", "443"] # or your custom ports
  }

  source_ranges = ["0.0.0.0/0"]
  target_tags   = ["${var.cluster_name}-gke-node"] # must match your GKE node tags
}