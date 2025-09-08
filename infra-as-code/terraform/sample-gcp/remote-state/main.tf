provider "google" {
  project = var.project_id
  region  = var.region
}

resource "random_string" "bckt_code" {
  length  = 5
  special = false
  upper   = false
}

resource "google_storage_bucket" "terraform_state" {
  name     = "${var.env_name}-bckt-${random_string.bckt_code.result}"
  location = var.region
  force_destroy = true

  versioning {
    enabled = true
  }

  uniform_bucket_level_access = true
}
