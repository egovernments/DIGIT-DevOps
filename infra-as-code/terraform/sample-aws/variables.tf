#
# Variables Configuration. Check for REPLACE to substitute custom values. Check the description of each
# tag for more information
#

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  default = "digit-go-eks" #REPLACE
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
  default = "5" #REPLACE IF NEEDED
}

variable "ssh_key_name" {
  description = "ssh key name, not required if your using spot instance types"
  default = "digit-go-eks" #REPLACE
}


variable "db_name" {
  description = "RDS DB name. Make sure there are no hyphens or other special characters in the DB name. Else, DB creation will fail"
  default = "digitgodb" #REPLACE
}

variable "db_username" {
  description = "RDS database user name"
  default = "digitdemo" #REPLACE
}

#DO NOT fill in here. This will be asked at runtime
variable "db_password" {}

variable "public_key" {
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCOan8WhMbiSs2GEON8aEcqiqERa2z4PQVa5btMFgw6SpYyTHtQiUrpvQVi0wMUab4UGPLB+82RzMK11oPZ6jxsfKi+X23q7IS09fHo7nTGrlfMHClDoFqJ4nwB5L+nDfGn/y4a8gns4DCtI2BcstXal207G6r6h3o0mIxDPJp0FsSuvQcRBbZfQeEWSjZH7xtp+uomhAHM/wniTj/Iu/KtVogDzhMj6pYRjus4ZUqUvjEJK4v+cXJv9vEbRYhTIz0GPRplA//xUSoHQhVHBFC+hN4VzVNr8kPPxKje4N0/VV8/wu3eLf63sjT5ca/3E6BxNeDkwHliA3B1ylTQaSJX" 
  description = "ssh key"
}

## change ssh key_name eg. digit-quickstart_your-name

variable "key_name" {
  default = "digit-go-ssh"  
  description = "ssh key name"
}

