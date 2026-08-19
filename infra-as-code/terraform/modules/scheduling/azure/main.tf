locals {
  # First run is "tomorrow" at the configured wall-clock time in the given UTC offset.
  # Using tomorrow's date guarantees start_time is always in the future at apply
  # (Azure requires schedule start_time to be > 5 min in the future). The recurring
  # daily run time is taken from the time-of-day portion below.
  first_run_date   = formatdate("YYYY-MM-DD", timeadd(timestamp(), "24h"))
  scale_up_start   = "${local.first_run_date}T${var.scale_up_time}:00${var.schedule_utc_offset}"
  scale_down_start = "${local.first_run_date}T${var.scale_down_time}:00${var.schedule_utc_offset}"
}

resource "azurerm_automation_account" "this" {
  name                = "${var.environment}-nodepool-automation"
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

# Let the Automation Account's managed identity manage (scale) the AKS node pools.
resource "azurerm_role_assignment" "automation_aks" {
  scope                = var.aks_cluster_id
  role_definition_name = "Azure Kubernetes Service Contributor Role"
  principal_id         = azurerm_automation_account.this.identity[0].principal_id
}

# The main node pool lives in a custom VNet subnet. Writing/scaling an agent pool in a
# custom subnet re-validates the linked action Microsoft.Network/virtualNetworks/subnets/join/action
# on that subnet. The AKS Contributor role has no Network permissions, so without this the
# scale fails with LinkedAuthorizationFailed. Network Contributor includes subnets/join.
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

resource "azurerm_automation_runbook" "scaler" {
  name                    = "${var.environment}-nodepool-scaler"
  location                = var.location
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  log_verbose             = true
  log_progress            = true
  runbook_type            = "PowerShell"
  description             = "Scale the AKS main node pool to a target count (0 at night / desired in the morning)."

  content = file("${path.module}/runbook.ps1")

  depends_on = [azurerm_automation_module.az_aks]
}

# ---------------- Scale UP (morning) ----------------
resource "azurerm_automation_schedule" "scale_up" {
  name                    = "${var.environment}-scale-up"
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  frequency               = "Week"
  interval                = 1
  week_days               = var.schedule_week_days
  timezone                = var.schedule_timezone
  start_time              = local.scale_up_start
  description             = "Scale main node pool up to desired count (weekdays only)"

  # start_time is recomputed each plan (uses timestamp()); only the time-of-day
  # matters after creation, so ignore drift to avoid perpetual diffs / recreation.
  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "scale_up" {
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  runbook_name            = azurerm_automation_runbook.scaler.name
  schedule_name           = azurerm_automation_schedule.scale_up.name

  # NOTE: Automation lowercases parameter names, so the keys here are lowercase.
  parameters = {
    subscriptionid = var.subscription_id
    resourcegroup  = var.resource_group
    clustername    = var.aks_cluster_name
    nodepoolname   = var.node_pool_name
    nodecount      = tostring(var.desired_count)
  }
}

# ---------------- Scale DOWN (night) ----------------
resource "azurerm_automation_schedule" "scale_down" {
  name                    = "${var.environment}-scale-down"
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  frequency               = "Week"
  interval                = 1
  week_days               = var.schedule_week_days
  timezone                = var.schedule_timezone
  start_time              = local.scale_down_start
  description             = "Scale main node pool down to 0 (weekday evenings; stays down over the weekend)"

  lifecycle {
    ignore_changes = [start_time]
  }
}

resource "azurerm_automation_job_schedule" "scale_down" {
  resource_group_name     = var.resource_group
  automation_account_name = azurerm_automation_account.this.name
  runbook_name            = azurerm_automation_runbook.scaler.name
  schedule_name           = azurerm_automation_schedule.scale_down.name

  parameters = {
    subscriptionid = var.subscription_id
    resourcegroup  = var.resource_group
    clustername    = var.aks_cluster_name
    nodepoolname   = var.node_pool_name
    nodecount      = "0"
  }
}
