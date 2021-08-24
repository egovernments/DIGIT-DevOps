# Copyright 2017, 2019, Oracle Corporation and/or affiliates.  All rights reserved.
# Licensed under the Universal Permissive License v 1.0 as shown at https://oss.oracle.com/licenses/upl

# Identity and access parameters
variable "api_fingerprint" {
  description = "Fingerprint of oci api private key."
  type        = string
  default = "1d:02:e6:2b:87:99:cd:ec:ca:e9:f6:7a:ef:fa:01:32"
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
}

# general oci parameters
variable "compartment_id" {
  description = "The compartment id where to create all resources."
  type        = string
  default = "ocid1.tenancy.oc1..aaaaaaaa6bezzujxhk3hgjiatq2cbnq54t6jtvsv2ftim4zdekaua4ahqzja"
}

variable "private_key_path" {
  description = "private key path"
}

variable "compartment_ocid" {
  default = "ocid1.tenancy.oc1..aaaaaaaa6bezzujxhk3hgjiatq2cbnq54t6jtvsv2ftim4zdekaua4ahqzja"
}

variable "private_key_oci" {
  default = "~/.oci/oci_api_key.pem"
}

variable "public_key_oci" {
  default = "~/.oci/oci_api_key_public.pem"
}

variable "dns-label" {
  default = "test"
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
  default = "oci-test"
}
