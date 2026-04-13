terraform {
  backend "gcs" {
    bucket = "<terraform_state_bucket_name>"  # Replace with the name after creating remote state bucket
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

data "google_client_openid_userinfo" "me" {}

resource "google_kms_key_ring" "sops_ring" {
  name     = "${var.env_name}-sops-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "sops_key" {
  name            = "${var.env_name}-sops-key"
  key_ring        = google_kms_key_ring.sops_ring.id
}

resource "google_kms_crypto_key_iam_member" "sops_user_binding" {
  crypto_key_id = google_kms_crypto_key.sops_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "user:${data.google_client_openid_userinfo.me.email}"
}

module "network" {
  source               = "../modules/network/gcp"
  region               = var.region
  environment          = var.env_name
  project_id           = var.project_id
  vpc_name             = "${var.env_name}-vpc"
  private_subnet_name  = "${var.env_name}-private-subnet"
  private_subnet_cidr  = var.private_subnet_cidr
  public_subnet_name   = "${var.env_name}-public-subnet"
  public_subnet_cidr   = var.public_subnet_cidr
  force_peering_cleanup = var.force_peering_cleanup
}

module "db" {
  source = "../modules/db/gcp"
  region                 = var.region
  db_instance_name       = "${var.env_name}-db"
  db_cpu                 = var.db_cpu
  db_memory_mb           = var.db_memory_mb
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
  source              = "../modules/kubernetes/gcp"
  cluster_name        = var.env_name
  zone                = var.zone
  k8s_version         = var.gke_version
  node_machine_type   = var.node_machine_type
  desired_node_count  = var.desired_node_count
  min_node_count      = var.min_node_count
  max_node_count      = var.max_node_count
  node_disk_size_gb   = var.node_disk_size_gb
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.private_subnet.name
  spot_enabled        = true

  depends_on = [module.network, time_sleep.wait_for_db]
}

