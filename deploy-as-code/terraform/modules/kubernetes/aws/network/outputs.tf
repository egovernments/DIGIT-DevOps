output "vpc_id" {
  value = "${aws_vpc.vpc.id}"
}

output "private_subnets" {
  value = aws_subnet.private_subnet.*.id
}

output "public_subnets" {
  value = aws_subnet.public_subnet.*.id
}

output "master_nodes_sg_id" {
  value = "${aws_security_group.master_nodes_sg.id}"
}

output "worker_nodes_sg_id" {
  value = "${aws_security_group.worker_nodes_sg.id}"
}

output "rds_db_sg_id" {
  value = "${aws_security_group.rds_db_sg.id}"
}