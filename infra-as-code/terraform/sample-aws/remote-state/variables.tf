variable "bucket_name" {
  validation {
    condition = (
      length(var.bucket_name) >= 3 &&
      length(var.bucket_name) <= 63 &&
      can(regex("^([a-z0-9][a-z0-9.-]*[a-z0-9])$", var.bucket_name)) &&
      !can(regex("\\.\\.", var.bucket_name)) &&
      !can(regex("^\\d+\\.\\d+\\.\\d+\\.\\d+$", var.bucket_name)) &&
      !can(regex("^xn--", var.bucket_name)) &&
      !can(regex("^sthree-", var.bucket_name)) &&
      !can(regex("^amzn-s3-demo-", var.bucket_name)) &&
      !can(regex("-s3alias$", var.bucket_name)) &&
      !can(regex("--ol-s3$", var.bucket_name)) &&
      !can(regex("\\.mrap$", var.bucket_name)) &&
      !can(regex("--x-s3$", var.bucket_name)) &&
      !can(regex("--table-s3$", var.bucket_name))
    )
    error_message = "Invalid S3 bucket name. It must be 3-63 characters long, lowercase, begin/end with letter or digit, not contain '..', not look like IP, and must avoid reserved prefixes/suffixes."
  }
}

variable "region" {}