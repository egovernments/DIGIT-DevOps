provider "aws" {
  region = "ap-south-1"
}

resource "aws_s3_bucket" "terraform_state" {
  bucket = "single-instance-terraform-state"

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_versioning" "versioning" {
  bucket = aws_s3_bucket.terraform_state.id
  versioning_configuration {
    status = "Enabled"
  }
}


resource "aws_dynamodb_table" "terraform_state_lock" {
  name           = "single-instance-terraform-state"
  read_capacity  = 1
  write_capacity = 1
  hash_key       = "LockID"

  attribute {
    name = "LockID"
    type = "S"
  }
}
