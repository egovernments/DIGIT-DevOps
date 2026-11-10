variable "environment" {}
variable "resource_group" {}
variable "location" {}
variable "subscription_id" {}

# From the kubernetes module
variable "aks_cluster_id" {}
variable "aks_cluster_name" {}

# Subnet the node pool is attached to (needed for subnets/join on start)
variable "aks_subnet_id" {}

# Schedule times (local wall-clock, HH:MM) and timezone
variable "cluster_start_time" {}
variable "cluster_stop_time" {}
variable "schedule_timezone" {}
variable "schedule_utc_offset" {}

# Days the start/stop schedules run on
variable "schedule_week_days" {}
