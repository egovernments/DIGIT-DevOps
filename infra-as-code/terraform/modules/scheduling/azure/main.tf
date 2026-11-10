locals {
  # First run is "tomorrow" at the configured wall-clock time in the given UTC offset.
  # Using tomorrow's date guarantees start_time is always in the future at apply
  # (Azure requires schedule start_time to be > 5 min in the future). The recurring
  # daily run time is taken from the time-of-day portion below.
  first_run_date   = formatdate("YYYY-MM-DD", timeadd(timestamp(), "24h"))
  cluster_start_at = "${local.first_run_date}T${var.cluster_start_time}:00${var.schedule_utc_offset}"
  cluster_stop_at  = "${local.first_run_date}T${var.cluster_stop_time}:00${var.schedule_utc_offset}"
}

resource "azurerm_automation_account" "this" {
  name                = "${var.environment}-cluster-automation"
  location            = var.location
  resource_group_name = var.resource_group
  sku_name            = "Basic"

  identity {
    type = "SystemAssigned"
  }

  tags = {
    Environment = var.environment
  }
}

# Let the Automation Account's managed identity start and stop the cluster.
# "Azure Kubernetes Service Contributor Role" grants Microsoft.ContainerService/
# managedClusters/*, which covers the start/action and stop/action operations.
resource "azurerm_role_assignment" "automation_aks" {
  scope                = var.aks_cluster_id
  role_definition_name = "Azure Kubernetes Service Contributor Role"
  principal_id         = azurerm_automation_account.this.identity[0].principal_id
}

# The node pool lives in a custom VNet subnet. Starting the cluster re-creates the
# VMSS instances in that subnet, which re-validates the linked action
# Microsoft.Network/virtualNetworks/subnets/join/action. The AKS Contributor role
# has no Network permissions, so without this the start can fail with
# LinkedAuthorizationFailed. Network Contributor includes subnets/join.
resource "azurerm_role_assignment" "automation_subnet_join" {
  scope                = var.aks_subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_automation_account.this.identity[0].principal_id
}

# The runbook uses Az cmdlets, but Automation Accounts ship only the legacy AzureRM
# modules by default. Import Az.Accounts and Az.Aks (Az.Aks depends on Az.Accounts).
resource "azurerm_automation_module" "az_accounts" {
  name                    = "Az.Accounts"
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.Accounts"
  }
}

resource "azurerm_automation_module" "az_aks" {
  name                    = "Az.Aks"
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name

  module_link {
    uri = "https://www.powershellgallery.com/api/v2/package/Az.Aks"
  }

  depends_on = [azurerm_automation_module.az_accounts]
}

resource "azurerm_automation_runbook" "power" {
  name                    = "${var.environment}-cluster-power"
  location                = var.location
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  description             = "Start or stop the AKS cluster (stopped overnight to save cost)."

  content = file("${path.module}/runbook.ps1")

  depends_on = [azurerm_automation_module.az_aks]
}

# ---------------- START (morning) ----------------
resource "azurerm_automation_schedule" "start" {
  name                    = "${var.environment}-cluster-start"
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  frequency               = "Week"
  interval                = 1
  week_days               = var.schedule_week_days
  timezone                = var.schedule_timezone
  start_time              = local.cluster_start_at
  description             = "Start the AKS cluster"

  # start_time is recomputed each plan (uses timestamp()); only the time-of-day
  # matters after creation, so ignore drift to avoid perpetual diffs / recreation.
  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "start" {
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  runbook_name            = azurerm_automation_runbook.power.name
  schedule_name           = azurerm_automation_schedule.start.name

  # NOTE: Automation lowercases parameter names, so the keys here are lowercase.
  parameters = {
    subscriptionid = var.subscription_id
    resourcegroup  = var.resource_group
    clustername    = var.aks_cluster_name
    action         = "Start"
  }
}

# ---------------- STOP (evening) ----------------
resource "azurerm_automation_schedule" "stop" {
  name                    = "${var.environment}-cluster-stop"
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  frequency               = "Week"
  interval                = 1
  week_days               = var.schedule_week_days
  timezone                = var.schedule_timezone
  start_time              = local.cluster_stop_at
  description             = "Stop the AKS cluster (deallocates every node)"

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "stop" {
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  runbook_name            = azurerm_automation_runbook.power.name
  schedule_name           = azurerm_automation_schedule.stop.name

  parameters = {
    subscriptionid = var.subscription_id
    resourcegroup  = var.resource_group
    clustername    = var.aks_cluster_name
    action         = "Stop"
  }
}
