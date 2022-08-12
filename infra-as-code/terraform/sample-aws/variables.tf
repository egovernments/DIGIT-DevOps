#
# Variables Configuration
#

# Name of the Kubernetes cluster
variable "cluster_name" {
  default = "my-first-eks" #REPLACE
}

variable "vpc_cidr_block" {
  default = "192.168.0.0/16"
}

#Configure availability zones configuration for VPC. Leave as default for India.
#Recommendation is to have subnets in at least two availability zones.
variable "network_availability_zones" {
  default = ["ap-south-1b", "ap-south-1a"] #REPLACE IF NEEDED
}

#Amazon EKS runs and scales the Kubernetes control plane across multiple AWS Availability Zones to 
#ensure high availability. Specify a comma separated list to have a cluster spanning multiple zones. Note
#that this will have cost implications
variable "availability_zones" {
  default = ["ap-south-1b"] #REPLACE IF NEEDED
}

variable "kubernetes_version" {
  default = "1.20"
}

variable "instance_type" {
  default = "m4.xlarge"
}

#eGov recommended defaults.
variable "override_instance_types" {
  default = ["r5a.large", "r5ad.large", "r5d.large", "m4.xlarge"]
  
}

#eGov recommended default. 
variable "number_of_worker_nodes" {
  default = "5"
}

variable "ssh_key_name" {
  default = "my-first-eks"
}

variable "bucket_name" {
  default = "try-workshop" #REPLACE
}

# RDS DB name. Make sure there are no hyphens or other special
#characters in the DB name. Else, DB creation will fail.
variable "db_name" {
default = "digittest" #REPLACE
}

#RDS database user name
variable "db_username" {
default = "egovdemo" #REPLACE
}

#DO NOT fill in here. This will be asked at runtime
variable "db_password" {}

