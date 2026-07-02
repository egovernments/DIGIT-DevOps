terraform {
  backend "gcs" {
    bucket = <terraform_state_bucket_name>  # Replace with the name after creating remote state bucket
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
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.20.0"
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
data "google_client_config" "current" {}
data "google_project" "current" {
  project_id = var.project_id
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
  bucket = <terraform_state_bucket_name>
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

resource "google_kms_key_ring" "gke_storage_ring" {
  name     = "${var.env_name}-gke-storage-keyring"
  location = var.region
}

resource "google_kms_crypto_key" "gke_storage_key" {
  name            = "${var.env_name}-gke-storage-key"
  key_ring        = google_kms_key_ring.gke_storage_ring.id
  rotation_period = "7776000s"
}

resource "google_kms_crypto_key_iam_member" "gke_storage_compute_binding" {
  crypto_key_id = google_kms_crypto_key.gke_storage_key.id
  role          = "roles/cloudkms.cryptoKeyEncrypterDecrypter"
  member        = "serviceAccount:service-${data.google_project.current.number}@compute-system.iam.gserviceaccount.com"
}

module "network" {
  source               = "../modules/network/gcp"
  region               = var.region
  project_id           = var.project_id
  vpc_name             = "${var.env_name}-vpc"
  private_subnet_name  = "${var.env_name}-private-subnet"
  private_subnet_cidr  = var.private_subnet_cidr
  public_subnet_name   = "${var.env_name}-public-subnet"
  public_subnet_cidr   = var.public_subnet_cidr
  flow_logs            = var.flow_logs
  flow_logs_sampling   = var.flow_logs_sampling
  flow_logs_metadata   = var.flow_logs_metadata
  force_peering_cleanup = var.force_peering_cleanup

  tags = {
    Environment = var.env_name
  }

  depends_on = [time_sleep.wait_for_api_activation]
}

module "db" {
  source                 = "../modules/db/gcp"
  region                 = var.region
  db_instance_name       = "${var.env_name}-db"
  db_instance_tier       = var.db_instance_tier
  db_disk_size_gb        = var.db_disk_size_gb
  db_max_connections     = var.db_max_connections
  vpc_id                 = module.network.vpc_id
  db_name                = var.db_name
  db_username            = var.db_username
  db_password            = var.db_password
  db_version             = var.db_version

  depends_on = [module.network]
}

resource "time_sleep" "wait_for_db" {
  depends_on = [module.db]
  create_duration = "60s"
  destroy_duration = "60s"
}

module "kubernetes" {
  source              = "../modules/kubernetes/gcp"
  project_id          = var.project_id
  cluster_name        = var.env_name
  zone                = var.zone
  k8s_version         = var.gke_version
  node_machine_type   = var.node_machine_type
  desired_node_count  = var.desired_node_count
  min_node_count      = var.min_node_count
  max_node_count      = var.max_node_count
  node_disk_size_gb   = var.node_disk_size_gb
  node_disk_type      = var.gke_cmek_disk_type
  boot_disk_kms_key   = google_kms_crypto_key.gke_storage_key.id
  vpc_id              = module.network.vpc_id
  subnet_id           = module.network.private_subnet.name
  cluster_resource_labels = merge({
    environment = var.env_name
  }, var.cluster_resource_labels)

  depends_on = [module.network, time_sleep.wait_for_db, google_kms_crypto_key_iam_member.gke_storage_compute_binding]
}

provider "kubernetes" {
  host                   = "https://${module.kubernetes.gke_cluster.endpoint}"
  token                  = data.google_client_config.current.access_token
  cluster_ca_certificate = base64decode(module.kubernetes.gke_cluster.master_auth[0].cluster_ca_certificate)
}

resource "kubernetes_storage_class" "gke_cmek_pd" {
  depends_on = [module.kubernetes, google_kms_crypto_key_iam_member.gke_storage_compute_binding]

  metadata {
    name = var.gke_cmek_storage_class_name
  }

  storage_provisioner    = "pd.csi.storage.gke.io"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true
  volume_binding_mode    = "WaitForFirstConsumer"

  parameters = {
    type                    = var.gke_cmek_disk_type
    disk-encryption-kms-key = google_kms_crypto_key.gke_storage_key.id
  }
}