variable "project_id" {
  default     = <GCP_PROJECT_ID>
  description = "GCP project to create the bucket in"
}

variable "region" {
  default     = <GCP_REGION>
  description = "GCP region for the bucket"
}

variable "bucket_name" {
  description = "Name of the GCS bucket to store Terraform state"
  type        = string
  default     = <terraform_state_bucket_name>
  validation {
    condition = (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9_-]*[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^goog", var.bucket_name)) &&      # reserved "goog" prefix
      !can(regex("google|g00gle", var.bucket_name)) # cannot contain "google"
    )
    error_message = <<EOT
State bucket name must follow GCS bucket naming rules:
- Be 3 to 63 characters long
- Contain only lowercase letters, numbers, hyphens and underscores (no dots: dotted names require domain verification)
- Start and end with a letter or number
- Not begin with the "goog" prefix
- Not contain "google" (or close misspellings such as g00gle)
EOT
  }
}
