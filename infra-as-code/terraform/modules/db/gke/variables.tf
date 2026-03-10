variable db_version {
  description = "The version of of the database"
}
variable region {
  description = "The region of of the database"
}
variable db_tier {
  description = "The machine tier (First Generation) or type (Second Generation). Reference: https://cloud.google.com/sql/pricing"
}
variable db_activation_policy {
  description = "Specifies when the instance should be active. Options are ALWAYS, NEVER or ON_DEMAND"
}
variable db_disk_autoresize {
  description = "Second Generation only. Configuration to increase storage size automatically."
}
variable db_disk_size {
  description = "Second generation only. The size of data disk, in GB. Size of a running instance cannot be reduced but can be increased."
}
variable db_disk_type {
  description = "Second generation only. The type of data disk: PD_SSD or PD_HDD"
}
variable db_pricing_plan {
  description = "First generation only. Pricing plan for this instance, can be one of PER_USE or PACKAGE"
}
variable db_instance_access_cidr {
  description = "The IPv4 CIDR to provide access the database instance"
}
# database settings
variable db_name {
  description = "Name of the default database to create"
}
variable db_charset {
  description = "The charset for the default database"
  default = ""
}
variable db_collation {
  description = "The collation for the default database. Example for MySQL databases: 'utf8_general_ci'"
  default = ""
}
# user settings
variable db_user_name {
  description = "The name of the default user"
}
variable db_user_host {
  description = "The host for the default user"
  default = "%"
}
variable db_user_password {
  description = "The password for the default user. If not set, a random one will be generated and available in the generated_user_password output variable."
  default = ""
}

variable env_name{
}

variable "module_depends_on" {
  description = "List of modules or resources this module depends on."
  type        = list(any)
  default     = []
}