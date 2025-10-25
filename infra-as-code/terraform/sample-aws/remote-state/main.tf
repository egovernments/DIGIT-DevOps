provider "aws" {
  region = var.region
}

# Generate a short random suffix
resource "random_id" "bucket_suffix" {
  byte_length = 3  # generates 6 hex characters
}

locals {
  bucket_name = lower("${var.cluster_name}-s3-state-${random_id.bucket_suffix.hex}")
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "${local.bucket_name}"

  lifecycle {
    prevent_destroy = false

    precondition {
      condition = (
      length(local.bucket_name) >= 3 &&
      length(local.bucket_name) <= 63 &&
      can(regex("^([a-z0-9][a-z0-9.-]*[a-z0-9])$", local.bucket_name)) &&
      !can(regex("\\.\\.", local.bucket_name)) &&
      !can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", local.bucket_name)) &&
      !can(regex("^xn--", local.bucket_name)) &&
      !can(regex("^sthree-", local.bucket_name)) &&
      !can(regex("^amzn-s3-demo-", local.bucket_name)) &&
      !can(regex("-s3alias$", local.bucket_name)) &&
      !can(regex("--ol-s3$", local.bucket_name)) &&
      !can(regex("\\.mrap$", local.bucket_name)) &&
      !can(regex("--x-s3$", local.bucket_name)) &&
      !can(regex("--table-s3$", local.bucket_name))
    )
    error_message = "Invalid S3 bucket name. It must be 3-63 characters long, lowercase, begin/end with letter or digit, not contain '..', not look like IP, and must avoid reserved prefixes/suffixes."
    }
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "${local.bucket_name}"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
