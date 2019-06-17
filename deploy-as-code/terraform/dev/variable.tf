#Azure Credentails read from Environment Variables
#Example :
#export TF_VAR_SUBSCRIPTION_ID=
#export TF_VAR_CLIENT_ID=
#export TF_VAR_CLIENT_SECRET=
#export TF_VAR_TENANT_ID=

variable "SUBSCRIPTION_ID" {}
variable "CLIENT_ID" {}
variable "CLIENT_SECRET" {}
variable "TENANT_ID" {}


variable "project" {
  default = ""
}

variable "env" {
    default = ""
}

variable "location" {
	default = "SouthIndia"
}

variable "az_cidr" {
    description = "CIDR for the whole VPC"
    default = "10.0.0.0/16"
} 

variable "dmz_cidrs" {
    description = "CIDR for public subnet"
    default = "10.0.1.0/24"
}

variable "ssh_public_key" {
	default = ""
}

# Apache Loadbalancer
variable "frontend" {
  type    = "map"
  default = {
    count           = "1"
    vm_size         = "Standard_B2s"
    volume_size     = "30"
    admin_username  = "azureuser"
    admin_password  = "uthoo8aht3air2Fe"
  }
}

# Application Server 
variable "application" {
  type    = "map"
  default = {
    count             = "1"
    vm_size           = "Standard_B2ms"
    volume_size       = "30"
    admin_username    = "azureuser"
    admin_password    = "keiF5bui5sioPoh4"
  }
}

#Elasticsearch Server
variable "elasticsearch" {
  type    = "map"
  default = {
    count         	= "1"
    vm_size 	      = "Standard_B2ms"
    volume_size   	= "30"
    admin_username  = "azureuser"
    admin_password  = "Eewi6peiz2chechi"
  }
}

#PostgreSQL Server
variable "postgresql" {
  type    = "map"
  default = {
    count         	= "1"
    vm_size 	      = "Standard_F2s"
    volume_size   	= "10"
    version		  	  = "9.6"
    admin_username	= "digitadmin"
    admin_password	= "feci4ahG9wai4eiw"
  }
}