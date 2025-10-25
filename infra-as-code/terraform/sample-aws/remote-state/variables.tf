variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  validation {
    condition = (
      length(var.cluster_name) <= 20 &&
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]*$", var.cluster_name))
    )
    error_message = "Cluster name must start with an alphanumeric character, contain only alphanumerics, hyphens (-), or underscores (_), and be no longer than 30 characters."
  }
}

variable "region" {}