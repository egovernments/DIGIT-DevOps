# Copyright 2017, 2019, Oracle Corporation and/or affiliates.  All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Identity and access parameters
variable "api_fingerprint" {
  description = "Fingerprint of oci api private key."
  type        = string
  default = "67:e6:70:0d:e3:09:4d:4c:48:62:78:e2:f8:0c:7f:d8"
}

variable "region" {
  # List of regions: https://docs.cloud.oracle.com/iaas/Content/General/Concepts/regions.htm#ServiceAvailabilityAcrossRegions
  description = "The oci region where resources will be created."
  type        = string
  default = "ap-mumbai-1"
}

variable "tenancy_id" {
  description = "The tenancy id in which to create the resources."
  type        = string
  default = "ocid1.tenancy.oc1..aaaaaaaa6bezzujxhk3hgjiatq2cbnq54t6jtvsv2ftim4zdekaua4ahqzja"
}

variable "user_id" {
  description = "The id of the user that terraform will use to create the resources."
  type        = string
  default = "ocid1.user.oc1..aaaaaaaamdyszcddszxay7uajmgekwew53g5oy66amfp7nl2gkawp5ygl5fa"
}

# general oci parameters
variable "compartment_id" {
  description = "The compartment id where to create all resources."
  type        = string
  default = "ocid1.tenancy.oc1..aaaaaaaa6bezzujxhk3hgjiatq2cbnq54t6jtvsv2ftim4zdekaua4ahqzja"
}

variable "private_key_path" {
  default = ""
}

variable "compartment_ocid" {
  default = "ocid1.tenancy.oc1..aaaaaaaa6bezzujxhk3hgjiatq2cbnq54t6jtvsv2ftim4zdekaua4ahqzja"
}

variable "private_key_oci" {
  default = ""
}

variable "public_key_oci" {
  default = ""
}

variable "vcn_cidr" {
  default = "10.0.0.0/16"
}

variable "kubernetes_version" {
   default = "v1.20.8"
}

variable "node_pool_size" {
  default = 1
}

variable "Shape" {
# default = "VM.Standard.E3.Flex"
  default = "VM.Standard.E2.2"
}

variable "ClusterName" {
  default = "OKECluster"
}

variable "vol_instance_count" {
  default = 1
}

variable "vol_name" {
  default = "egov_test"
}
variable "block_storage_sizes_in_gbs" {
  default = 50
}

variable "nodepoolname" {
  default = "OKENodePool"
}