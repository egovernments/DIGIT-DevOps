resource "google_sql_database_instance" "postgresql" {
  name = "${var.env_name}-db"
  region = "${var.region}"
  database_version = "${var.db_version}"
  
  settings {
    tier = "${var.db_tier}"
    activation_policy = "${var.db_activation_policy}"
    disk_autoresize = "${var.db_disk_autoresize}"
    disk_size = "${var.db_disk_size}"
    disk_type = "${var.db_disk_type}"
    pricing_plan = "${var.db_pricing_plan}"
   
    maintenance_window {
      day  = "7"  # sunday
      hour = "3" # 3am
    }
   
    backup_configuration {
      binary_log_enabled = true
      enabled = true
      start_time = "00:00"
    }
   
    ip_configuration {
      ipv4_enabled = "true"
      authorized_networks {
        value = "${var.db_instance_access_cidr}"
      }
    }
  }
}

resource "null_resource" "module_depends_on" {
  triggers = {
    value = length(var.module_depends_on)
 }
}
resource "random_id" "user_password" {
  keepers = {
    name = google_sql_database_instance.postgresql.name
  }
  byte_length = 8
  depends_on  = [null_resource.module_depends_on, google_sql_database_instance.postgresql]
}

# create database
resource "google_sql_database" "postgresql_db" {
  name = "${var.db_name}"
  instance = "${google_sql_database_instance.postgresql.name}"
  charset = "${var.db_charset}"
  collation = "${var.db_collation}"
}

