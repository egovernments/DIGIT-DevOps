#
# Variables Configuration. Check for REPLACE to substitute custom values. Check the description of each
# tag for more information
#

variable "cluster_name" {
  description = "Name of the Kubernetes cluster"
  default = "unified-dev" #REPLACE
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
  default     = ["t4g.xlarge", "t4g.2xlarge"]
}

variable "min_worker_nodes" {
  description = "eGov recommended below worker node counts as default for min nodes"
  default = "4" #REPLACE IF NEEDED
}

variable "desired_worker_nodes" {
  description = "eGov recommended below worker node counts as default for desired nodes"
  default = "5" #REPLACE IF NEEDED
}

variable "max_worker_nodes" {
  description = "eGov recommended below worker node counts as default for max nodes"
  default = "10" #REPLACE IF NEEDED
}

variable "ssh_key_name" {
  description = "ssh key name, not required if your using spot instance types"
  default = "unified-dev" #REPLACE
}


variable "db_name" {
  description = "RDS DB name. Make sure there are no hyphens or other special characters in the DB name. Else, DB creation will fail"
  default = "unifieddevdb" #REPLACE
}

variable "db_username" {
  description = "RDS database user name"
  default = "unifieddev" #REPLACE
}

#DO NOT fill in here. This will be asked at runtime
variable "db_password" {}

variable "public_key" {
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCrfbaDFN3FmjUoVUx4YH1eHPruFbWz6JGPfSKTwIqT75xFzU/Q6KCa3Xa6FnEOpcUKXej95pkeUnXywohojF6FrNak5p5xfGmmwC8UA9s5UxsI7flBKVnjsAbcRuxoa/AtOzg4Cizz6zQLl2JZAivZU1PwZjIJo8dcum9bjZYVHwZc3csKJ2nYgpcQrV8AWnfKtLvl5WNfNF0i5bWOieNLKiEc5DtsKYbQ6umrhhCaoGcH0S/Gy6w0PPSnnfl/AWXO7ckFtEXQbdz9Y15zeUFKgUsbklXxmC6D37BkPGu+IjCZSOttPV+PRM0Dnf0jQLvMV0UhEkguD9ALC5xikqNlFyPH5bGetWDxtLbn61tnoOIYG6lXAdk2Oe35yWWt3ZgcccWtYuRwDo0ofBwY9jWOkEcCefDyYg+S7h1VzNsbB9DsFv0vPcaxHcZK8bLdyhnz1+9rXy/flbiS5kE0O97aZ4zm4wAmqiivN2wWhUez18k2Mcs= demo@demo" 
  description = "ssh key"
}

## change ssh key_name eg. digit-quickstart_your-name

variable "key_name" {
  default = "unified-dev"  
  description = "ssh key name"
}

variable "iam_user_arn" {
  description = "Provide the IAM user arn which you are using to create infrastructure"
  default = "arn:aws:iam::349271159511:user/egov-unified-dev-kube-deployer"
}

variable "enable_ClusterAutoscaler" {
  description = "Enable the Cluster Autoscaler."
  type        = bool
  default     = true
}
