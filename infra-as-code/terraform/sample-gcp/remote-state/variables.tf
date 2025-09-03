variable "project_id" {
  description = "GCP project to create the bucket in"
}

variable "region" {
  description = "GCP region for the bucket"
}

variable "env_name" {
  description = "Name of the GCS bucket to store Terraform state"
}
