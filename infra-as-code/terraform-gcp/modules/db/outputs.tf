output "db_instance_name" {
  value = google_sql_database_instance.postgres_instance.name
}

output "db_instance_private_ip" {
  value = google_sql_database_instance.postgres_instance.private_ip_address
}

output "db_name" {
  value = google_sql_database.custom_db.name
}

output "db_username" {
  value = google_sql_user.postgres_admin.name
}

output "db_password" {
  value = google_sql_user.postgres_admin.password
}