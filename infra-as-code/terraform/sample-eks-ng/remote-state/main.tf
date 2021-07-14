provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "ifix-dev-terraform-state-1"

  versioning {
    enabled = true
  }

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "ifix-dev-terraform-state-1"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
