variable "project_id" {
  default = "digit-egov"
  description = "Name of the GCp Project"
}

variable "env_name" {
  default = "egov-sample-gke"
  description = "Name of the env"
}

variable "region" {
  default = "us-central1"
  description = "region"
}

variable "gke_username" {
  default     = ""
  description = "gke username"
}

variable "gke_password" {
  default     = ""
  description = "gke password"
}

variable "min_node_count" {
  default = 2
  description = "mininum number of gke nodes"
}

variable "max_node_count" {
  default = 4
  description = "maximum number of gke nodes"
}

variable "num_nodes" {
  default = "3"
}

variable "machine_type" {
  default     = "n1-standard-1"
  description = "machine type"
}

variable "initial_node_count" {
  default     = "2"
  description = "initial node count"
}

variable "cidr_range" {
  default     = "10.10.0.0/24"
  description = "cidr_range"
}