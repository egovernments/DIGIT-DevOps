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
  description = "Name of the env (GKE cluster) and environment name"
  type        = string
  default     = <ENVIRONMENT_NAME>
  validation {
    condition = (
      length(var.env_name) >= 3 &&
      length(var.env_name) <= 40 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.env_name)) &&
      !can(regex("--", var.env_name)) # no consecutive hyphens
    )
    error_message = <<EOT
Environment name must:
- Be 3 to 40 characters long
- Contain only lowercase letters, numbers, and hyphens
- Start with a lowercase letter and end with a letter or number
- Not contain consecutive hyphens
EOT
  }
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
  default = "1.35.8-gke.1225000"
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
  description = "Cloud SQL (PostgreSQL) database name"
  type        = string
  default     = <DATABASE_NAME>
  validation {
    condition = (
      length(var.db_name) >= 3 &&
      length(var.db_name) <= 40 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.db_name))
    )
    error_message = <<EOT
DB name must:
- Be 3 to 40 characters long
- Contain only letters and numbers (no hyphens or special characters)
- Start with a letter
EOT
  }
}

variable "db_username" {
  description = "Cloud SQL (PostgreSQL) user name"
  type        = string
  default     = <DATABASE_USERNAME>
  validation {
    condition = (
      length(var.db_username) >= 3 &&
      length(var.db_username) <= 40 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9]*$", var.db_username))
    )
    error_message = <<EOT
DB user name must:
- Be 3 to 40 characters long
- Contain only letters and numbers (no hyphens or special characters)
- Start with a letter
EOT
  }
}

variable "db_password" {
  description = "Cloud SQL (PostgreSQL) user password (provided at plan/apply time via -var)"
  type        = string
  validation {
    condition = (
      length(var.db_password) >= 6 &&
      length(var.db_password) <= 16 &&
      can(regex("^[a-z][a-zA-Z0-9@#]*$", var.db_password))
    )
    error_message = <<EOT
DB password must:
- Be 6 to 16 characters long
- Start with a lowercase letter
- Use only letters, numbers, and @ or # (no other symbols)
EOT
  }
}

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