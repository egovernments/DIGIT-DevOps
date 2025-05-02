terraform {
  backend "gcs" {
    bucket = "egov-gcp-test-bucket"  # Replace with the name after creating remote state bucket
    prefix  = "terraform/state"
  }

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = ">= 5.0"
    }
    time = {
      source = "hashicorp/time"
      version = ">= 0.9.0"
    }
  }

  required_version = ">= 1.3.0"
}

provider "google" {
  project = var.project_id
  region  = var.region
  zone    = var.zone
}

resource "google_project_service" "enable_apis" {
  for_each = toset([
    "compute.googleapis.com",
    "container.googleapis.com",
    "servicenetworking.googleapis.com",
    "sqladmin.googleapis.com"
  ])
  service = each.key
  disable_on_destroy         = true
  disable_dependent_services = true
}

resource "time_sleep" "wait_for_api_activation" {
  depends_on = [google_project_service.enable_apis]
  create_duration = "60s"
  destroy_duration = "60s"
}

resource "google_service_account" "s3_app_user" {
  account_id   = "${var.env_name}-s3-client"
  display_name = "S3-compatible access for AWS SDK app"
}

resource "google_storage_bucket_iam_member" "writer" {
  bucket = "egov-gcp-test-bucket"
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.s3_app_user.email}"
}

resource "null_resource" "generate_hmac_key" {
  provisioner "local-exec" {
    command = <<EOT
      gcloud iam service-accounts keys create ./hmac-key.json \
        --iam-account=${google_service_account.s3_app_user.email} \
        --project=${var.project_id}

      gcloud storage hmac create \
        ${google_service_account.s3_app_user.email} \
        --project=${var.project_id} \
        --format=json > ./gcs-hmac-key.json
    EOT
  }

  depends_on = [google_service_account.s3_app_user]
}

module "network" {
  source               = "./modules/networking"
  region               = var.region
  project_id           = var.project_id
  vpc_name             = "${var.env_name}-vpc"
  private_subnet_name  = "${var.env_name}-private-subnet"
  private_subnet_cidr  = var.private_subnet_cidr
  public_subnet_name   = "${var.env_name}-public-subnet"
  public_subnet_cidr   = var.public_subnet_cidr
  force_peering_cleanup = var.force_peering_cleanup

  tags = {
    Environment = var.env_name
  }

  depends_on = [time_sleep.wait_for_api_activation]
}

module "db" {
  source = "./modules/db"
  region                 = var.region
  db_instance_name       = "${var.env_name}-db"
  db_instance_tier       = var.db_instance_tier
  db_disk_size_gb        = var.db_disk_size_gb
  db_max_connections     = var.db_max_connections
  vpc_id                 = module.network.vpc_id
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password

  depends_on = [module.network]
}

resource "time_sleep" "wait_for_db" {
  depends_on = [module.db]
  create_duration = "60s"
  destroy_duration = "60s"
}

module "kubernetes" {
  source              = "./modules/kubernetes"
  cluster_name        = var.env_name
  zone                = var.zone
  k8s_version         = var.gke_version
  node_machine_type   = var.node_machine_type
  desired_node_count  = var.desired_node_count
  min_node_count      = var.min_node_count
  max_node_count      = var.max_node_count
  node_disk_size_gb      = var.node_disk_size_gb
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.private_subnet.name

  depends_on = [module.network, time_sleep.wait_for_db]
}

