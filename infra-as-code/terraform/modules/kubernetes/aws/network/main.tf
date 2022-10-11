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


resource "aws_security_group" "worker_nodes_sg" {
  name        = "nodes-${var.cluster_name}"
  description = "Security group for all worker nodes in the cluster"
  vpc_id      = "${aws_vpc.vpc.id}"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = "${
    tomap({
      "Name" = "nodes-${var.cluster_name}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
}

resource "aws_security_group" "master_nodes_sg" {
  name        = "masters-${var.cluster_name}"
  description = "Master nodes security group"
  vpc_id      = "${aws_vpc.vpc.id}"

  tags = "${
    tomap({
      "Name" = "masters-${var.cluster_name}"
      "kubernetes.io/cluster/${var.cluster_name}" = "shared"
      "KubernetesCluster" = "${var.cluster_name}"
    })
  }"
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

resource "aws_security_group_rule" "master_nodes_egress_workers" {
  description              = "Allow outbound traffic to worker nodes" 
  from_port                = 10250
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.master_nodes_sg.id}"
  source_security_group_id = "${aws_security_group.worker_nodes_sg.id}"
  type                     = "egress"
}

resource "aws_security_group_rule" "master_nodes_ingress_workers" {
  description              = "Allow worker nodes to communicate with cluster API server" 
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.master_nodes_sg.id}"
  source_security_group_id = "${aws_security_group.worker_nodes_sg.id}"
  type                     = "ingress"
}


resource "aws_security_group_rule" "worker_nodes_ingress_self" {
  description              = "Allow node to communicate with each other"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "-1"
  security_group_id        = "${aws_security_group.worker_nodes_sg.id}"
  source_security_group_id = "${aws_security_group.worker_nodes_sg.id}"
  type                     = "ingress"
}

resource "aws_security_group_rule" "worker_nodes_ingress_cluster" {
  description              = "Allow worker Kubelets and pods to receive communication from the cluster control plane"
  from_port                = 1025
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.worker_nodes_sg.id}"
  source_security_group_id = "${aws_security_group.master_nodes_sg.id}"
  type                     = "ingress"
}

resource "aws_security_group_rule" "rds_db_ingress_workers" {
  description              = "Allow worker nodes to communicate with RDS database" 
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = "${aws_security_group.rds_db_sg.id}"
  source_security_group_id = "${aws_security_group.worker_nodes_sg.id}"
  type                     = "ingress"
}