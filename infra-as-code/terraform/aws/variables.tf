#
# Variables Configuration. Check for REPLACE to substitute custom values. Check the description of each
# tag for more information
#

variable "cluster_name" {
  description = "Name of the Kubernetes cluster (EKS) and environment name"
  type        = string
  default     = <cluster_name> #REPLACE
  validation {
    condition = (
      length(var.cluster_name) >= 3 &&
      length(var.cluster_name) <= 40 &&
      can(regex("^[a-z][a-z0-9-]*[a-z0-9]$", var.cluster_name)) &&
      !can(regex("--", var.cluster_name)) # no consecutive hyphens
    )
    error_message = <<EOT
Cluster name must:
- Be 3 to 40 characters long
- Contain only lowercase letters, numbers, and hyphens
- Start with a lowercase letter and end with a letter or number
- Not contain consecutive hyphens
EOT
  }
}

variable "vpc_cidr_block" {
  description = "CIDR block"
  default = "10.30.0.0/16"
}


variable "network_availability_zones" {
  description = "Configure availability zones configuration for VPC. Leave as default for India. Recommendation is to have subnets in at least two availability zones"
  default = ["ap-south-1a", "ap-south-1b"] #REPLACE IF NEEDED
}

variable "availability_zones" {
  description = "Amazon EKS runs and scales the Kubernetes control plane across multiple AWS Availability Zones to ensure high availability. Specify a comma separated list to have a cluster spanning multiple zones. Note that this will have cost implications"
  default = ["ap-south-1b"] #REPLACE IF NEEDED
}

variable "kubernetes_version" {
  description = "kubernetes version"
  default = "1.35"
}

variable "db_version" {
  description = "DB version"
  default = "15.18"
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
  type        = string
  default     = <db_name> #REPLACE
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
  description = "RDS database user name"
  type        = string
  default     = <db_username> #REPLACE
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

variable "ami_id" {
  description = "Provide the AMI ID that supports your eks version for karpenter"
  default = {
    id   = "" #Replace if needed
    name = "" #Replace if needed
  }
}

variable "ami_family" {
  description = "Provide the AMI Family which is compatible with your ami_id provisioned by karpenter"
  default = {
    name = "AL2023" #Replace if needed
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

variable "enable_ClusterAutoscaler" {
  description = "Enable the Cluster Autoscaler."
  type        = bool
  default     = false
}

#DO NOT fill in here. This will be asked at runtime
variable "db_password" {
  description = "RDS master password (provided at plan/apply time via -var)"
  type        = string
  validation {
    condition = (
      length(var.db_password) >= 8 &&
      length(var.db_password) <= 16 &&
      can(regex("^[a-z][a-zA-Z0-9#]*$", var.db_password))
    )
    error_message = <<EOT
DB password must:
- Be 8 to 16 characters long
- Start with a lowercase letter
- Use only letters, numbers, and # (RDS does not allow @, /, quotes or spaces)
EOT
  }
}

variable cloudwatch_eks_log_group_retention_in_days {
  default = "7"
}

