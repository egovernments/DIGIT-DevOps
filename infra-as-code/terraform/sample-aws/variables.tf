#
# Variables Configuration. Check for REPLACE to substitute custom values. Check the description of each
# tag for more information
#

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

variable "vpc_cidr_block" {
  description = "CIDR block"
  default = "192.168.0.0/16"
}

variable "kubernetes_version" {
  description = "kubernetes version"
  default = "1.32"
}

variable "db_version" {
  description = "DB version"
  default = "15.12"
}

variable "db_instance_class" {
  description = "DB instance class"
  default = "db.t4g.medium"
}

variable "architecture" {
  description = "Architecture for worker nodes (x86_64 or arm64)"
  type        = string
  default     = "x86_64"
  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "Architecture must be either x86_64 or arm64."
  }
}

variable "capacity_type" {
  description = "Capacity type for worker nodes (SPOT or ON_DEMAND)"
  type        = string
  default     = "ON_DEMAND"
  validation {
    condition     = contains(["SPOT", "ON_DEMAND"], var.capacity_type)
    error_message = "Instance Capacity type must be either SPOT or ON_DEMAND."
  }
}

# Map of architecture → instance types
variable "instance_types_map" {
  description = "Map of instance types per architecture"
  type = map(list(string))
  default = {
    x86_64 = ["m5a.xlarge"]
    arm64  = ["t4g.xlarge"]
  }
}

# Optional override variable (if users want to specify directly)
variable "instance_types" {
  description = "List of instance types to use (optional — overrides architecture defaults)"
  type        = list(string)
  default     = []
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
  default = demodb #REPLACE
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
  default = demouser #REPLACE
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
    id   = "ami-0b6753867a45581f3"
    name = "bottlerocket-aws-k8s-1.32-x86_64-v1.49.0-713f44ce"
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

variable "enable_ClusterAutoscaler" {
  description = "Enable the Cluster Autoscaler."
  type        = bool
  default     = false
}

#DO NOT fill in here. This will be asked at runtime
variable "db_password" {
  description = "RDS database upassword"
  default = demo1234 #REPLACE
}
