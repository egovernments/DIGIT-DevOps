resource "google_compute_network" "vpc_network" {
  name                    = var.vpc_name
  auto_create_subnetworks = false
}

resource "google_compute_subnetwork" "public_subnet" {
  name                     = var.public_subnet_name
  ip_cidr_range            = var.public_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc_network.id
  private_ip_google_access = false
}

resource "google_compute_subnetwork" "private_subnet" {
  name                     = var.private_subnet_name
  ip_cidr_range            = var.private_subnet_cidr
  region                   = var.region
  network                  = google_compute_network.vpc_network.id
  private_ip_google_access = true
}

resource "google_compute_global_address" "private_service_ip" {
  name          = "${var.environment}-private-service-access-ip"
  purpose       = "VPC_PEERING"
  address_type  = "INTERNAL"
  prefix_length = 16
  network       = google_compute_network.vpc_network.id
}

resource "google_compute_router" "nat_router" {
  name    = "${var.vpc_name}-nat-router"
  network = google_compute_network.vpc_network.name
  region  = var.region
}

resource "google_compute_router_nat" "nat_gw" {
  name                               = "${var.vpc_name}-nat-gateway"
  router                             = google_compute_router.nat_router.name
  region                             = var.region
  nat_ip_allocate_option             = "AUTO_ONLY"
  source_subnetwork_ip_ranges_to_nat = "LIST_OF_SUBNETWORKS"

  subnetwork {
    name                    = google_compute_subnetwork.private_subnet.name
    source_ip_ranges_to_nat = ["ALL_IP_RANGES"]
  }
}

resource "google_service_networking_connection" "private_vpc_connection" {
  network                 = google_compute_network.vpc_network.id
  service                 = "servicenetworking.googleapis.com"
  reserved_peering_ranges = [google_compute_global_address.private_service_ip.name]

  lifecycle {
    prevent_destroy = false
    ignore_changes  = []
  }
}

resource "null_resource" "force_delete_peering" {
  triggers = {
    run_cleanup = var.force_peering_cleanup ? timestamp() : "no-op"
    vpc_name   = var.vpc_name
    project_id = var.project_id
  }

  provisioner "local-exec" {
    when    = destroy
    command = <<EOT
      echo "Attempting manual fallback peering delete via gcloud..."
      gcloud compute networks peerings delete servicenetworking-googleapis-com \
        --network=${self.triggers.vpc_name} \
        --project=${self.triggers.project_id} \
        --quiet || echo "Peering may already be deleted or failed gracefully"
    EOT
  }

  depends_on = [google_service_networking_connection.private_vpc_connection]
}

