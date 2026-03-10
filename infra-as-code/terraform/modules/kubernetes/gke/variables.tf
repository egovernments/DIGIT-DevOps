variable "project_id" {
  description = "project id"
}

variable "region" {
  description = "region"
}

variable "gke_username" {
  description = "gke username"
}

variable "gke_password" {
  description = "gke password"
}

variable "min_node_count" {
  description = "mininum number of gke nodes"
}

variable "max_node_count" {
  description = "maximum number of gke nodes"
}

variable "machine_type" {
  description = "machine type"
}

variable "initial_node_count" {
  description = "initial node count"
}

variable "cidr_range" {
  description = "cidr_range"
}