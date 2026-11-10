<#
.SYNOPSIS
    Start or stop an AKS cluster.
    Called by two schedules:
      - evening: Action = Stop   (every node is deallocated)
      - morning: Action = Start
.NOTES
    Auth uses the Automation Account's system-assigned managed identity, which is
    granted "Azure Kubernetes Service Contributor Role" on the cluster by Terraform.

    Stopping the cluster deallocates ALL nodes, including the System pool, which is
    why this works on a single-node-pool cluster where scaling a pool to 0 cannot.
    Persistent volumes and cluster state are retained; workloads resume on start.
#>

param(
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$ClusterName,
    [Parameter(Mandatory = $true)][ValidateSet("Start", "Stop")][string]$Action
)

$ErrorActionPreference = "Stop"

Write-Output "Connecting with managed identity..."
Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity | Out-Null
Set-AzContext -Subscription $SubscriptionId | Out-Null
Write-Output "Subscription: $SubscriptionId"

$cluster = Get-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName
$state = $cluster.PowerState.Code
Write-Output "BEFORE: $ClusterName powerState=$state provisioning=$($cluster.ProvisioningState)"

# A start/stop issued against a cluster mid-operation fails, so skip rather than error.
if ($cluster.ProvisioningState -ne "Succeeded") {
    Write-Output "Cluster is in provisioning state '$($cluster.ProvisioningState)'. Skipping $Action."
    return
}

# Idempotency: the schedule may fire against an already-correct state (e.g. a
# manual stop the evening before, or a retry).
if ($Action -eq "Stop") {
    if ($state -eq "Stopped") {
        Write-Output "Already stopped. Nothing to do."
    }
    else {
        Write-Output "Stopping $ClusterName..."
        Stop-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName | Out-Null
    }
}
else {
    if ($state -eq "Running") {
        Write-Output "Already running. Nothing to do."
    }
    else {
        Write-Output "Starting $ClusterName..."
        Start-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName | Out-Null
    }
}

$after = Get-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName
Write-Output "AFTER: powerState=$($after.PowerState.Code)"
Write-Output "Done."
