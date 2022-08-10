output "rds_postgres_address" {
  value = "${aws_db_instance.rds_postgres.address}"
}

output "db_instance_endpoint" {
  value = "${aws_db_instance.rds_postgres.endpoint}"
}


output "db_instance_name" {
  description = "The database name"
  value       = "${aws_db_instance.rds_postgres.name}"
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = "${aws_db_instance.rds_postgres.username}"
  sensitive   = true
}

output "db_instance_port" {
  description = "The database port"
  value       = "${aws_db_instance.rds_postgres.port}"
}