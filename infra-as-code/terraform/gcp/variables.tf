variable "project_id" {
  default     = <GCP_PROJECT_ID>
  description = "Name of the GCP Project"
}

variable "region" {
  default     = <GCP_REGION>
}

variable "zone" {
  default = <GCP_AVAILABILITY_ZONE>
}

variable "env_name" {
  default     = <ENVIRONMENT_NAME>
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
  default = "1.34.8-gke.1000000"
}

variable "node_machine_type" {
  default = "n2d-highmem-2"            # Allocate as per quota available
}

variable "desired_node_count" {
  default = "3"
}

variable "min_node_count" {
  default = "3"                        # Allocate as per quota available
}

variable "max_node_count" {
  default = "4"                        # Allocate as per quota available
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

variable "db_version"{
  default = "POSTGRES_15"
}

variable "db_name" {
  default = <DATABASE_NAME>
}

variable "db_username" {
  default = <DATABASE_USERNAME>
}

variable "db_password" {}

variable "force_peering_cleanup" {
  default = false
}

variable "flow_logs" {
  default = false
}

variable "flow_logs_sampling" {
  default = 0.5
}

variable "flow_logs_metadata" {
  default = "INCLUDE_ALL_METADATA"
}

variable "gke_cmek_storage_class_name" {
  default = "gke-cmek-rwo"
}

variable "gke_cmek_disk_type" {
  default = "pd-standard"
}

variable "cluster_resource_labels" {
  type    = map(string)
  default = {}
}