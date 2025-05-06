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
  default = "1.28"
}

variable "instance_type" {
  description = "eGov recommended below instance type as a default"
  default = "r5ad.large"
}

variable "override_instance_types" {
  description = "Arry of instance types for SPOT instances"
  default = ["r5a.large", "r5ad.large", "r5d.large", "m4.xlarge"]
  
}

variable "number_of_worker_nodes" {
  description = "eGov recommended below worker node counts as default"
  default = "3" #REPLACE IF NEEDED
}

variable "ssh_key_name" {
  description = "ssh key name, not required if your using spot instance types"
  default = "digit-lts" #REPLACE
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
variable "db_password" {}

variable "public_key" {
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDPyFldf44vtDQaD2oAB1/UWg5a2jJc/R0XShPV4U305ph0V7IpYK9o6XpLIjyTivp6+A93+CNb1sw7l44P7gYpIjfJKKT+q/fwtWabGfp2L/0EBsNzonOsFVjFz9pCQr0kObVFW+TQ68bq/n2tXKsm2dw8woSMDk/c+M6o14JhUAw9mvQHuEPLWLV3v11QB9CZzN1l/yWebOREkN6rUZGI1PqkmOFSwSvSVyo+sMUhEaRbp7r/KoqNGWHsHAedV3Fqry1KxF9K8c8BEfW/xkat62h91ff42ODhitVAFHhukN8RCQsWoS0mC572aF4WGqzQc0P+2W1TAy6QQAPLTgBr"
  description = "ssh key"
}

## change ssh key_name eg. digit-quickstart_your-name



