variable "project_id" {
  default     = "mcs-gcp-test-1"
  description = "Name of the GCp Project"
}

variable "gcp_bucket" {
  default = "egov-gcp-test-bucket"
}

variable "region" {
  default     = "asia-south1"
  description = "region"
}

variable "zone" {
  default = "asia-south1-a"
}

variable "env_name" {
  default     = "gcp-test"
  description = "Name of the env"
}

variable "private_subnet_cidr" {
  default     = "10.10.0.0/24"
  description = "cidr_range for private subnet"
}

variable "public_subnet_cidr" {
  default     = "10.10.64.0/19"
  description = "cidr_range for public subnet"
}

variable "gke_version" {
  default = "1.32.2-gke.1182003"
}

variable "node_machine_type" {
  default = "n2d-highmem-2" #"n2-highmem-2"
}

variable "desired_node_count" {
  default = "3"
}

variable "min_node_count" {
  default = "3"
}

variable "max_node_count" {
  default = "3"
}

variable "node_disk_size_gb" {
  default = "50"
}

variable "db_instance_tier" {
  default = "db-f1-micro"
}

variable "db_disk_size_gb" {
  default = "10"
}

variable "db_max_connections" {
  default = "100"
}

variable "db_name" {
  default = "gcptestdb"
}

variable "db_username" {
  default = "gcptest"
}

variable "db_password" {}

variable "force_peering_cleanup" {
  default = false
}