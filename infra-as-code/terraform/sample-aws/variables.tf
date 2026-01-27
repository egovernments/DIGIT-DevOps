#
# Variables Configuration. Check for REPLACE to substitute custom values. Check the description of each
# tag for more information
#

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  default = "digit-lts" #REPLACE
}

variable "vpc_cidr_block" {
  description = "CIDR block"
  default = "192.168.0.0/16"
}


variable "network_availability_zones" {
  description = "Configure availability zones configuration for VPC. Leave as default for India. Recommendation is to have subnets in at least two availability zones"
  default = ["ap-south-1b", "ap-south-1a"] #REPLACE IF NEEDED
}

variable "availability_zones" {
  description = "Amazon EKS runs and scales the Kubernetes control plane across multiple AWS Availability Zones to ensure high availability. Specify a comma separated list to have a cluster spanning multiple zones. Note that this will have cost implications"
  default = ["ap-south-1b"] #REPLACE IF NEEDED
}

variable "kubernetes_version" {
  description = "kubernetes version"
  default = "1.33"
}

variable "instance_types" {
  description = "eGov recommended below instance type as a default"
  default = ["t4g.xlarge"]
}

variable "min_worker_nodes" {
  description = "eGov recommended below worker node counts as default for min nodes"
  default = "1" #REPLACE IF NEEDED
}

variable "desired_worker_nodes" {
  description = "eGov recommended below worker node counts as default for desired nodes"
  default = "4" #REPLACE IF NEEDED
}

variable "max_worker_nodes" {
  description = "eGov recommended below worker node counts as default for max nodes"
  default = "5" #REPLACE IF NEEDED
}


variable "db_name" {
  description = "RDS DB name. Make sure there are no hyphens or other special characters in the DB name. Else, DB creation will fail"
  default = "digitltsdb" #REPLACE
}

variable "db_username" {
  description = "RDS database user name"
  default = "digitlts" #REPLACE
}

#DO NOT fill in here. This will be asked at runtime
#variable "db_password" {}

variable "ami_id" {
  description = "Provide the AMI ID that supports your eks version"
  default = {
    id   = "ami-0431db82d7dc815dd"
    name = "amazon-eks-arm64-node-1.31-v20250610"
  }
}

variable "enable_karpenter" {
  description = "Enable the karpenter."
  type        = bool
  default     = false
}




