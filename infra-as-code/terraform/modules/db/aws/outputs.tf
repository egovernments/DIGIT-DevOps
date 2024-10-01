output "rds_postgres_address" {
  value = "${aws_db_instance.rds_postgres.address}"
}

output "db_instance_endpoint" {
  value = "${aws_db_instance.rds_postgres.endpoint}"  # Adjusted to match the module's actual output
}

output "db_instance_name" {
  description = "The database name"
  value       = "${aws_db_instance.rds_postgres.identifier}"  # Adjusted to match the module's actual output
}

output "db_instance_username" {
  description = "The master username for the database"
  value       = "${aws_db_instance.rds_postgres.username}"  # Adjusted to match the module's actual output
  sensitive   = true
}

output "db_instance_port" {
  description = "The database port"
  value       = "${aws_db_instance.rds_postgres.port}"  # Adjusted to match the module's actual output
}
