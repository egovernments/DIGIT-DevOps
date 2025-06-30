#
# Variables Configuration. Check for REPLACE to substitute custom values. Check the description of each
# tag for more information
#

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  validation {
    condition = (
      length(var.cluster_name) <= 30 &&
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]*$", var.cluster_name))
    )
    error_message = "Cluster name must start with an alphanumeric character, contain only alphanumerics, hyphens (-), or underscores (_), and be no longer than 30 characters."
  }
}

variable "eks_managed_node_group" {
  description = "Name of the Kubernetes cluster"
  validation {
    condition = (
      length(var.cluster_name) <= 30 &&
      can(regex("^[a-zA-Z0-9][a-zA-Z0-9_-]*$", var.eks_managed_node_group))
    )
    error_message = "Managed nodegroup name must start with an alphanumeric character, contain only alphanumerics, hyphens (-), or underscores (_), and be no longer than 30 characters."
  }
}

variable "vpc_cidr_block" {
  description = "CIDR block"
  default = "192.168.0.0/16"
}

variable "kubernetes_version" {
  description = "kubernetes version"
  default = "1.31"
}

variable "instance_types" {
  description = "Arry of instance types for SPOT instances"
  default = ["m5a.xlarge", "r5ad.xlarge"]
  
}

variable "min_worker_nodes" {
  description = "eGov recommended below worker node counts as default for min nodes"
  default = "1" #REPLACE IF NEEDED
}

variable "desired_worker_nodes" {
  description = "eGov recommended below worker node counts as default for desired nodes"
  default = "3" #REPLACE IF NEEDED
}

variable "max_worker_nodes" {
  description = "eGov recommended below worker node counts as default for max nodes"
  default = "5" #REPLACE IF NEEDED
}

variable "db_name" {
  description = "RDS DB name. Make sure there are no hyphens or other special characters in the DB name. Else, DB creation will fail"
  validation {
    condition = (
      length(var.db_name) >= 1 &&
      length(var.db_name) <= 63 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_name))
    )
    error_message = "Database name must start with a letter and contain only alphanumeric characters and underscores (no hyphens), and be 1–63 characters long."
  }
}

variable "db_username" {
  description = "RDS database user name"
  validation {
    condition = (
      length(var.db_username) >= 1 &&
      length(var.db_username) <= 63 &&
      can(regex("^[a-zA-Z][a-zA-Z0-9_]*$", var.db_username)) &&
      lower(var.db_username) != "admin" &&
      lower(var.db_username) != "root" &&
      lower(var.db_username) != "rdsadmin"
    )
    error_message = "Username must start with a letter, contain only letters, numbers, and underscores, be 1–63 characters long, and not be one of the reserved names: admin, root, rdsadmin."
  }
}

variable "ami_id" {
  description = "Provide the AMI ID that supports your eks version"
  default = {
    id   = "ami-0d1008f82aca87cb9"
    name = "amazon-eks-node-1.30-v20241024"
  }
}

variable "filestore_namespace" {
  description = "Provide the namespace to create filestore secret"
  default = "egov" #REPLACE  
}

variable "enable_karpenter" {
  description = "Enable the karpenter."
  type        = bool
  default     = false
}

variable "region" {}

