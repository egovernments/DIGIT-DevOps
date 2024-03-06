# VPC
resource "google_compute_network" "vpc" {
  name                    = "${var.project_id}-vpc"
  auto_create_subnetworks = "false"
}

# Subnet
resource "google_compute_subnetwork" "subnet" {
  name          = "${var.project_id}-subnet"
  region        = "${var.region}"
  network       = "${google_compute_network.vpc.name}"
  ip_cidr_range = "${var.cidr_range}"
}

# GKE cluster
resource "google_container_cluster" "primary" {
  name     = "${var.project_id}"
  location = "${var.region}"

  remove_default_node_pool = true
  initial_node_count       = "${var.initial_node_count}"

  network    = "${google_compute_network.vpc.name}"
  subnetwork = "${google_compute_subnetwork.subnet.name}"

  master_auth {
    username = "${var.gke_username}"
    password = "${var.gke_password}"

    client_certificate_config {
      issue_client_certificate = false
    }
  }
}

resource "google_container_node_pool" "primary_nodes" {
  name       = "${google_container_cluster.primary.name}-node-pool"
  location   = "${var.region}"
  cluster    = "${google_container_cluster.primary.name}"

  initial_node_count = "${var.initial_node_count}"

  autoscaling {
    min_node_count = "${var.min_node_count}"
    max_node_count = "${var.max_node_count}"
  }

  node_config {
    oauth_scopes = [
      "https://www.googleapis.com/auth/logging.write",
      "https://www.googleapis.com/auth/monitoring",
    ]

    labels = {
      env = "${var.project_id}"
    }

    machine_type = "${var.machine_type}"
    tags         = ["gke-node", "${var.project_id}"]
    metadata = {
      disable-legacy-endpoints = "true"
    }
  }
}