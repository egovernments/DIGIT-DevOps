output "rds_postgres_address" {
  value = "${aws_db_instance.rds_postgres.address}"
}

