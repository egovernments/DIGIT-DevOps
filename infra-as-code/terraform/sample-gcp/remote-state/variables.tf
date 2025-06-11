variable "project_id" {
  default     = "digit-platform"
  description = "GCP project to create the bucket in"
}

variable "region" {
  default     = "asia-south1"
  description = "GCP region for the bucket"
}

variable "bucket_name" {
  default     = "digit-platform-bucket"
  description = "Name of the GCS bucket to store Terraform state"
}
