variable "project_id" {
  default     = "<GCP_PROJECT_ID>"
  description = "GCP project to create the bucket in"
}

variable "region" {
  default     = "<GCP_REGION>"
  description = "GCP region for the bucket"
}

variable "bucket_name" {
  default     = "<terraform_state_bucket_name>"
  description = "Name of the GCS bucket to store Terraform state"
}
