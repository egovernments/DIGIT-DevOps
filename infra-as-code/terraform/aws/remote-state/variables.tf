variable "bucket_name" {
  description = "S3 bucket for Terraform remote state (also used as the DynamoDB lock table name)"
  type        = string
  default     = <terraform_state_bucket_name>
  validation {
    condition = (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^[a-z0-9][a-z0-9-]*[a-z0-9]$", var.bucket_name)) &&
      !can(regex("^(xn--|sthree-|amzn-s3-demo-)", var.bucket_name)) && # reserved prefixes
      !can(regex("(-s3alias|--ol-s3)$", var.bucket_name))              # reserved suffixes
    )
    error_message = <<EOT
State bucket name must follow S3 bucket naming rules:
- Be 3 to 63 characters long
- Contain only lowercase letters, numbers, and hyphens (no dots: the Terraform S3 backend uses HTTPS virtual-host addressing)
- Start and end with a letter or number
- Not start with xn--, sthree-, or amzn-s3-demo-
- Not end with -s3alias or --ol-s3
EOT
  }
}