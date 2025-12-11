resource "google_sql_database_instance" "postgres_instance" {
  name             = var.db_instance_name
  region           = var.region
  database_version = "POSTGRES_15"

  settings {
    tier      = "db-custom-${var.db_cpu}-${var.db_memory_mb}"
    disk_size = var.db_disk_size_gb

    ip_configuration {
      ipv4_enabled    = false
      private_network = var.vpc_id
    }

    maintenance_window {
      day          = 7
      hour         = 2
      update_track = "stable"
    }

    activation_policy = "ALWAYS"

    database_flags {
      name  = "max_connections"
      value = var.db_max_connections
    }
  }

  deletion_protection = false
}

resource "google_sql_user" "postgres_admin" {
  name     = var.db_username
  instance = google_sql_database_instance.postgres_instance.name
  password = var.db_password

  depends_on = [google_sql_database_instance.postgres_instance]
}

resource "time_sleep" "wait_for_db" {
  depends_on = [google_sql_user.postgres_admin]
  create_duration = "10s"
  destroy_duration = "10s"
}

resource "google_sql_database" "custom_db" {
  name      = var.db_name
  instance  = google_sql_database_instance.postgres_instance.name
  charset   = var.db_charset
  collation = var.db_collation

  depends_on = [time_sleep.wait_for_db]
}
