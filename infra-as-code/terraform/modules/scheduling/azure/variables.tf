variable "environment" {}
variable "resource_group" {}
variable "location" {}
variable "subscription_id" {}

# From the kubernetes module
variable "aks_cluster_id" {}
variable "aks_cluster_name" {}
variable "node_pool_name" {}

# Subnet the main node pool is attached to (needed for subnets/join permission)
variable "aks_subnet_id" {}

# Morning target for the main node pool
variable "desired_count" {}

# Schedule times (local wall-clock, HH:MM) and timezone
variable "scale_up_time" {}
variable "scale_down_time" {}
variable "schedule_timezone" {}
variable "schedule_utc_offset" {}

# Days the schedules run on (weekdays only -> down over the weekend)
variable "schedule_week_days" {}
