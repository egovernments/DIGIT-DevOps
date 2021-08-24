# VPC Resources
#  * VPC
#  * Subnets
#  * Internet Gateway
#  * Route Table
#
resource "oci_core_vcn" "VCN" {
  cidr_block     = var.vcn_cidr
  compartment_id = var.tenancy_id
  display_name   = "${var.ClusterName}-vcn"
  dns_label     = var.dns-label
  freeform_tags = "${
    map(
      "Name", "${var.ClusterName}"
    )
  }"
}

resource "oci_core_subnet" "public_subnet" {
  count = 1
  cidr_block                 = "${cidrsubnet("${var.vcn_cidr}", 5, count.index)}"
  compartment_id             = var.tenancy_id
  display_name               = "${var.ClusterName}-Utility-subnet"
  dns_label                  = "Utility"
  prohibit_public_ip_on_vnic = false
  route_table_id             = oci_core_route_table.public_route_table.id
  vcn_id                     = oci_core_vcn.VCN.id
  security_list_ids          = [oci_core_security_list.public-security-list.id]

  freeform_tags = "${
    map(
      "SubnetType", "Utility",
      "KubernetesCluster", "${var.ClusterName}"
    )
  }"

}

resource "oci_core_subnet" "private_subnet" {
  count = 1
  cidr_block                 = "${cidrsubnet("${var.vcn_cidr}", 3, 2+count.index)}"
  compartment_id             = var.tenancy_id
  display_name               = "${var.ClusterName}-private-subnet"
  dns_label                  = "private"
  prohibit_public_ip_on_vnic = true
  route_table_id             = oci_core_route_table.private_route_table.id
  vcn_id                     = oci_core_vcn.VCN.id
  security_list_ids          = [oci_core_security_list.worker-security-list.id]

  freeform_tags = "${
    map(
      "SubnetType", "Private",
      "KubernetesCluster", "${var.ClusterName}"
    )
  }"
  
}

resource "oci_core_internet_gateway" "InternetGateway" {
  compartment_id = var.tenancy_id
  display_name   = "${var.ClusterName}-InternetGateway"
  vcn_id         = oci_core_vcn.VCN.id

  freeform_tags = "${
    map(
      "KubernetesCluster", "${var.ClusterName}"
    )
  }"
}

resource "oci_core_nat_gateway" "nat_gateway" {
    #Required
    compartment_id = var.tenancy_id
    vcn_id = oci_core_vcn.VCN.id
    #Optional
    display_name = "${var.ClusterName}-nat"
    public_ip_id = oci_core_public_ip.public_ip.id
    depends_on = [oci_core_internet_gateway.InternetGateway]

    freeform_tags = "${
    map(
      "KubernetesCluster", "${var.ClusterName}"
    )
  }"

}


resource "oci_core_public_ip" "public_ip" {
    #Required
    compartment_id = var.tenancy_id
    lifetime = "RESERVED"
    #Optional
    display_name = "${var.ClusterName}"
    #private_ip_id = oci_core_subnet.public_subnet[0].id
    depends_on = [oci_core_internet_gateway.InternetGateway]

    freeform_tags = "${
    map(
      "KubernetesCluster", "${var.ClusterName}"
    )
  }"

}


resource "oci_core_route_table" "private_route_table" {
  compartment_id = var.tenancy_id
  vcn_id         = oci_core_vcn.VCN.id
  display_name   = "${var.ClusterName}-private-route"
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id =  oci_core_nat_gateway.nat_gateway.id
  }

  freeform_tags = "${
    map(
      "KubernetesCluster", "${var.ClusterName}"
    )
  }"
}

resource "oci_core_route_table" "public_route_table" {
  compartment_id = var.tenancy_id
  vcn_id         = oci_core_vcn.VCN.id
  display_name   = "${var.ClusterName}-Utility-route"
  route_rules {
    destination       = "0.0.0.0/0"
    destination_type  = "CIDR_BLOCK"
    network_entity_id =  oci_core_internet_gateway.InternetGateway.id
  }

  freeform_tags = "${
    map(
      "KubernetesCluster", "${var.ClusterName}"
    )
  }"

}

resource "oci_core_security_list" "worker-security-list" {
  compartment_id = var.tenancy_id
  display_name   = "${var.ClusterName}-Workers-SecList"
  vcn_id         = oci_core_vcn.VCN.id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "6" // outbound TCP to the internet
    stateless   = false
  }

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "all"
    stateless   = true
  }

  ingress_security_rules {
    stateless = true

    protocol = "all"
    source   = "0.0.0.0/0"
  }

  ingress_security_rules {
    # ICMP 
    protocol = 1
    source   = "0.0.0.0/0"

    icmp_options {
      type = 3
      code = 4
    }
  }
  
  # NodePort ingress rules
  ingress_security_rules {
    protocol  = "6" // tcp
    source    = "0.0.0.0/0"
    stateless = true

    tcp_options {
      min = 30000
      max = 32767
    }
  }

  freeform_tags = "${
    map(
      "KubernetesCluster", "${var.ClusterName}"
    )
  }"

}

/*
 * - Allows all TCP traffic in/out.
 */
resource "oci_core_security_list" "public-security-list" {
  compartment_id = var.tenancy_id
  display_name   = "${var.ClusterName}-Utility-SecList"
  vcn_id         = oci_core_vcn.VCN.id

  egress_security_rules {
    destination = "0.0.0.0/0"
    protocol    = "6"
    stateless   = true
  }
  ingress_security_rules {
    protocol  = "6"
    source    = "0.0.0.0/0"
    stateless = true
  }

  freeform_tags = "${
    map(
      "KubernetesCluster", "${var.ClusterName}"
    )
  }"

}