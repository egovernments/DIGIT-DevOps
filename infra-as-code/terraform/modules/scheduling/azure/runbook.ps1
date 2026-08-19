<#
.SYNOPSIS
    Scale an AKS node pool to a target node count.
    Called by two schedules:
      - morning: NodeCount = <desired>
      - night:   NodeCount = 0
.NOTES
    Auth uses the Automation Account's system-assigned managed identity, which is
    granted "Azure Kubernetes Service Contributor Role" on the cluster by Terraform.
#>

param(
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$ClusterName,
    [Parameter(Mandatory = $true)][string]$NodePoolName,
    [Parameter(Mandatory = $true)][int]$NodeCount
)

$ErrorActionPreference = "Stop"

Write-Output "Connecting with managed identity..."
Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity | Out-Null
Set-AzContext -Subscription $SubscriptionId | Out-Null
Write-Output "Subscription: $SubscriptionId"

$pool = Get-AzAksNodePool -ResourceGroupName $ResourceGroup -ClusterName $ClusterName -Name $NodePoolName
Write-Output "BEFORE: mode=$($pool.Mode) count=$($pool.Count) autoscaler=$($pool.EnableAutoScaling)"

# Safety: a System pool can never be scaled to 0
if ($NodeCount -eq 0 -and $pool.Mode -eq "System") {
    throw "Node pool '$NodePoolName' is a System pool and cannot be scaled to 0."
}

# Idempotency: nothing to do if already at the target count with autoscaler off
if (-not $pool.EnableAutoScaling -and $pool.Count -eq $NodeCount) {
    Write-Output "Already at $NodeCount nodes. Nothing to do."
}
else {
    # Manual scaling requires the autoscaler to be off
    if ($pool.EnableAutoScaling) {
        Update-AzAksNodePool -ResourceGroupName $ResourceGroup -ClusterName $ClusterName -Name $NodePoolName -EnableAutoScaling:$false
    }
    Update-AzAksNodePool -ResourceGroupName $ResourceGroup -ClusterName $ClusterName -Name $NodePoolName -NodeCount $NodeCount
}

$after = Get-AzAksNodePool -ResourceGroupName $ResourceGroup -ClusterName $ClusterName -Name $NodePoolName
Write-Output "AFTER: count=$($after.Count)"
Write-Output "Done."
