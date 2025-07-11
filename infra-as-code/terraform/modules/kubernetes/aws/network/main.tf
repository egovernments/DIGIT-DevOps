#
# VPC Resources
#  * VPC
#  * Subnets
#  * Internet Gateway
#  * Route Table
#
resource "aws_vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr_block}"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = "${
    tomap({
      Name = "${var.cluster_name}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
    })
  }"
}

resource "aws_subnet" "public_subnet" {
  count = "${length(var.availability_zones)}"

  availability_zone = "${var.availability_zones[count.index]}"
  cidr_block        = "${cidrsubnet("${var.vpc_cidr_block}", 5, count.index)}" 
  vpc_id            = "${aws_vpc.vpc.id}"

  tags = "${
    tomap({
      Name = "utility-${var.availability_zones[count.index]}-${var.cluster_name}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "kubernetes.io/role/elb" = 1
      "SubnetType" = "Utility"
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
}

resource "aws_subnet" "private_subnet" {
  count = "${length(var.availability_zones)}"

  availability_zone = "${var.availability_zones[count.index]}"
  cidr_block        = "${cidrsubnet("${var.vpc_cidr_block}", 3, 2+count.index)}" 
  vpc_id            = "${aws_vpc.vpc.id}"

  tags = "${
    tomap({
      "Name" = "${var.availability_zones[count.index]}-${var.cluster_name}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "kubernetes.io/role/internal-elb" = 1
      "SubnetType" = "Private"
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
}

resource "aws_internet_gateway" "internet_gateway" {
  vpc_id = "${aws_vpc.vpc.id}"

  tags = "${
    tomap({
      "Name" = "${var.cluster_name}" 
      "kubernetes.io/cluster/${var.cluster_name}" = "shared" 
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
}

resource "aws_route_table" "public_route_table" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.internet_gateway.id}"
  }

    tags = "${
    tomap({
      "Name" = "public-${var.cluster_name}-rtb"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
}

resource "aws_route_table_association" "public" {
  count = "${length(aws_subnet.public_subnet.*.id)}"

  subnet_id      = "${aws_subnet.public_subnet.*.id[count.index]}"
  route_table_id = "${aws_route_table.public_route_table.id}"
}

resource "aws_eip" "eip" {
  vpc      = true
  depends_on = ["aws_internet_gateway.internet_gateway"]

    tags = "${
    tomap({
      "Name" = "eip-${var.cluster_name}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"  

}

resource "aws_nat_gateway" "nat" {
  allocation_id = "${aws_eip.eip.id}"
  subnet_id     = "${element(aws_subnet.public_subnet.*.id, 0)}"

  depends_on = ["aws_internet_gateway.internet_gateway"]

    tags = "${
    tomap({
      "Name" = "nat-gw-${var.cluster_name}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
}


resource "aws_route_table" "private_route_table" {
  vpc_id = "${aws_vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = "${aws_nat_gateway.nat.id}"
  }

    tags = "${
    tomap({
      "Name" = "private-${var.cluster_name}-rtb"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"  
}

resource "aws_route_table_association" "private" {
  count = "${length(aws_subnet.private_subnet.*.id)}"

  subnet_id      = "${aws_subnet.private_subnet.*.id[count.index]}"
  route_table_id = "${aws_route_table.private_route_table.id}"
}

resource "aws_security_group" "rds_db_sg" {
  name        = "db-${var.cluster_name}"
  description = "RDS Database security group"
  vpc_id      = "${aws_vpc.vpc.id}"

  tags = "${
    tomap({
      "Name" = "db-${var.cluster_name}"
    })
  }"
}