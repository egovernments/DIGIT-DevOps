#
# Variables Configuration. Check for REPLACE to substitute custom values. Check the description of each
# tag for more information
#

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  default = "unified-demo" #REPLACE
}

variable "vpc_cidr_block" {
  description = "CIDR block"
  default = "192.168.0.0/16"
}

variable "network_availability_zones" {
  description = "Configure availability zones configuration for VPC. Leave as default for India. Recommendation is to have subnets in at least two availability zones"
  default = ["ap-south-1a", "ap-south-1b"] #REPLACE IF NEEDED
}

variable "availability_zones" {
  description = "Amazon EKS runs and scales the Kubernetes control plane across multiple AWS Availability Zones to ensure high availability. Specify a comma separated list to have a cluster spanning multiple zones. Note that this will have cost implications"
  default = ["ap-south-1a"] #REPLACE IF NEEDED
}

variable "kubernetes_version" {
  description = "kubernetes version"
  default = "1.33"
}

variable "db_version" {
  description = "DB version"
  default = "15.12"
}

variable "db_instance_class" {
  description = "DB instance class"
  default = "db.t4g.large"
}

variable "architecture" {
  description = "Architecture for worker nodes (x86_64 or arm64)"
  type        = string
  default     = "arm64"
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
  default = "1" #REPLACE IF NEEDED
}

variable "max_worker_nodes" {
  description = "eGov recommended below worker node counts as default for max nodes"
  default = "1" #REPLACE IF NEEDED
}

variable "db_name" {
  description = "RDS DB name. Make sure there are no hyphens or other special characters in the DB name. Else, DB creation will fail"
  default = "unifieddemodb" #REPLACE
}

variable "db_username" {
  description = "RDS database user name"
  default = "unifieddemo" #REPLACE
}

variable "ami_id" {
  description = "Provide the AMI ID that supports your eks version"
  default = {
    id   = "ami-0474c4a8f9ad6ca62"
    name = "amazon-eks-node-al2023-arm64-standard-1.33-v20260129"
  }
}

variable "filestore_namespace" {
  description = "Provide the namespace to create filestore secret"
  default = "egov" #REPLACE  
}

variable "enable_karpenter" {
  description = "Enable the karpenter."
  type        = bool
  default     = true
}

variable "enable_ClusterAutoscaler" {
  description = "Enable the Cluster Autoscaler."
  type        = bool
  default     = false
}

#DO NOT fill in here. This will be asked at runtime
variable "db_password" {}

