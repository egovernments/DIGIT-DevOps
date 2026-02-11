#
# Variables Configuration. Check for REPLACE to substitute custom values. Check the description of each
# tag for more information
#

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  default = "unified-qa" #REPLACE
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
  description = "eGov recommended ARM64 instance types for better cost efficiency"
  default = ["t4g.xlarge", "t4g.2xlarge"]
}

variable "min_worker_nodes" {
  description = "eGov recommended below worker node counts as default for min nodes"
  default = "4" #REPLACE IF NEEDED
}

variable "desired_worker_nodes" {
  description = "eGov recommended below worker node counts as default for desired nodes"
  default = "6" #REPLACE IF NEEDED
}

variable "max_worker_nodes" {
  description = "eGov recommended below worker node counts as default for max nodes"
  default = "10" #REPLACE IF NEEDED
}

variable "ssh_key_name" {
  description = "ssh key name, not required if your using spot instance types"
  default = "unified-qa-ssh" #REPLACE
}


variable "db_name" {
  description = "RDS DB name. Make sure there are no hyphens or other special characters in the DB name. Else, DB creation will fail"
  default = "unifiedqadb" #REPLACE
}

variable "db_username" {
  description = "RDS database user name"
  default = "unifiedqa" #REPLACE
}

#DO NOT fill in here. This will be asked at runtime
variable "db_password" {}

variable "public_key" {
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCPWTCpDOJm32GgjYAqSZ0nf/tXcp4RcSDqEUtxa/TUwQduMelvnlZIIkN15QmwUo0sswf08qHWAgFFc2A/kfpokq5kmh5iiTO8Q/uFlW1lGjpl6c76/1DWo+BdnFQIW/2sfLaCuIceuTKyCsCMO3v08ghlbJcKTUgwBtbzStly1xeH7zo7jErIAf0+uezeKbjI5grbylbskdqcqIIp0i4/QYkZ9NB07gXCTUcHySfgf4Wa3KMVcDmECLc2JuD2KtiiQSK0AVU8cXa6Loc6eYmLa8Ut9mPDunkAxkZOKDMzhtCWDkwRUYWPvqQB0DckzaCVEmvVNKVpFjBZWxE6K9EH"
  description = "ssh key"
}

## change ssh key_name eg. digit-quickstart_your-name

variable "iam_user_arn" {
  description = "Provide the IAM user arn which you are using to create infrastructure"
  default = "arn:aws:iam::349271159511:user/unified-qa"
}


