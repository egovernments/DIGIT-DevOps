#
# Variables Configuration. Check for REPLACE to substitute custom values. Check the description of each
# tag for more information
#

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  default = "egov-staging" #REPLACE
}

variable "vpc_cidr_block" {
  description = "CIDR block"
  default = "10.1.64.0/19"
}


variable "network_availability_zones" {
  description = "Configure availability zones configuration for VPC. Leave as default for India. Recommendation is to have subnets in at least two availability zones"
  default = ["ap-south-1a", "ap-south-1b"] #REPLACE IF NEEDED
}

variable "availability_zones" {
  description = "Amazon EKS runs and scales the Kubernetes control plane across multiple AWS Availability Zones to ensure high availability. Specify a comma separated list to have a cluster spanning multiple zones. Note that this will have cost implications"
  default = ["ap-south-1a"] #REPLACE IF NEEDED
}

variable "availability_zone" {
  description = "RDS availability zone"
  default = ["ap-south-1b"] #REPLACE IF NEEDED
}

variable "kubernetes_version" {
  description = "kubernetes version"
  default = "1.29"
}

variable "instance_type" {
  description = "eGov recommended below instance type as a default"
  default = "m4.xlarge"
}

variable "override_instance_types" {
  description = "Arry of instance types for SPOT instances"
  default = ["r5a.large", "r5ad.large", "r5d.large", "m4.xlarge"]
  
}

variable "number_of_worker_nodes" {
  description = "eGov recommended below worker node counts as default"
  default = "7" #REPLACE IF NEEDED
}

variable "ssh_key_name" {
  description = "ssh key name, not required if your using spot instance types"
  default = "egov-staging" #REPLACE
}

variable "db_subnet_group" {
  default = "default-vpc-0f630338229cf5c1e"
}

variable "db_name" {
  description = "RDS DB name. Make sure there are no hyphens or other special characters in the DB name. Else, DB creation will fail"
  default = "egov-staging" #REPLACE
}

variable "db_username" {
  description = "RDS database user name"
  default = "egovdev" #REPLACE
}

#DO NOT fill in here. This will be asked at runtime
variable "db_password" {}

variable "public_key" {
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCrfbaDFN3FmjUoVUx4YH1eHPruFbWz6JGPfSKTwIqT75xFzU/Q6KCa3Xa6FnEOpcUKXej95pkeUnXywohojF6FrNak5p5xfGmmwC8UA9s5UxsI7flBKVnjsAbcRuxoa/AtOzg4Cizz6zQLl2JZAivZU1PwZjIJo8dcum9bjZYVHwZc3csKJ2nYgpcQrV8AWnfKtLvl5WNfNF0i5bWOieNLKiEc5DtsKYbQ6umrhhCaoGcH0S/Gy6w0PPSnnfl/AWXO7ckFtEXQbdz9Y15zeUFKgUsbklXxmC6D37BkPGu+IjCZSOttPV+PRM0Dnf0jQLvMV0UhEkguD9ALC5xikqNlFyPH5bGetWDxtLbn61tnoOIYG6lXAdk2Oe35yWWt3ZgcccWtYuRwDo0ofBwY9jWOkEcCefDyYg+S7h1VzNsbB9DsFv0vPcaxHcZK8bLdyhnz1+9rXy/flbiS5kE0O97aZ4zm4wAmqiivN2wWhUez18k2Mcs= demo@demo" 
  description = "ssh key"
}

## change ssh key_name eg. digit-quickstart_your-name

variable "key_name" {
  default = "digit-quickstart"  
  description = "ssh key name"
}

variable "iam_keybase_user" {
 default = "keybase:egovterraform"
}

