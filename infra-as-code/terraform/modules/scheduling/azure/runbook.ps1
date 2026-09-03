<#
.SYNOPSIS
    Stop or start the whole AKS cluster on a schedule (night down / morning up).

.DESCRIPTION
    Called by two schedules:
      - night:   Action = Stop
      - morning: Action = Start

    WHY CLUSTER STOP/START INSTEAD OF SCALING THE NODE POOL TO 0
    ------------------------------------------------------------
    This runbook used to call
        Update-AzAksNodePool -NodeCount 0
    which cordons and drains every node in the pool. Draining evicts pods, and
    eviction is refused when it would violate a PodDisruptionBudget. backbone has
    two PDBs -- elasticsearch-master-pdb and elasticsearch-data-pdb -- each with
    maxUnavailable=1 over 3 replicas, so desiredHealthy=2. Evicting one master
    leaves it Pending while its Azure managed disk detaches and reattaches, which
    drops currentHealthy to 2, which makes disruptionsAllowed 0, which makes the
    next master eviction in the same pass fail with 429 Too Many Requests. With
    $ErrorActionPreference = "Stop" that aborts the entire run. That is what
    killed the 2026-08-21T15:30 job, after which the nightly scale-down stopped
    working entirely.

    A PDB can never allow the last nodes in a pool to be drained -- that is
    precisely what a PDB is for. So draining is the wrong mechanism here.
    Loosening the PDB would be worse: 3 Elasticsearch masters need 2 healthy for
    quorum, and allowing 2 to go down at once turns the cluster red.

    Stop-AzAksCluster deallocates the node VMs instead of evicting pods, so no
    eviction is attempted and no PDB is consulted. It also stops the control
    plane and the System pool, so it saves more than scaling the User pool alone.
    Managed disks, PVCs and all cluster state are preserved across the cycle, and
    Start-AzAksCluster brings the pools back at their previous node counts --
    which is why this no longer needs NodePoolName or NodeCount.

.NOTES
    Auth uses the Automation Account's system-assigned managed identity, which
    holds "Azure Kubernetes Service Contributor Role" on the cluster. That role
    grants Microsoft.ContainerService/managedClusters/*, which already covers
    both stop/action and start/action -- no extra role assignment is needed.

    Automation lowercases parameter names, so the job schedule passes
    subscriptionid / resourcegroup / clustername / action. PowerShell parameter
    binding is case-insensitive, so these bind to the parameters below.
#>

param(
    [Parameter(Mandatory = $true)][string]$SubscriptionId,
    [Parameter(Mandatory = $true)][string]$ResourceGroup,
    [Parameter(Mandatory = $true)][string]$ClusterName,
    [Parameter(Mandatory = $true)][ValidateSet("Start", "Stop")][string]$Action
)

$ErrorActionPreference = "Stop"
# Stop-/Start-AzAksCluster implement ShouldProcess with a High confirm impact.
# A runbook is non-interactive, so leaving this at the default would block.
$ConfirmPreference = "None"

Write-Output "Connecting with managed identity..."
Disable-AzContextAutosave -Scope Process | Out-Null
Connect-AzAccount -Identity | Out-Null
Set-AzContext -Subscription $SubscriptionId | Out-Null
Write-Output "Subscription: $SubscriptionId"
Write-Output "Action:       $Action"

$cluster = Get-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName
$power = $cluster.PowerState.Code
$state = $cluster.ProvisioningState
Write-Output "BEFORE: power=$power provisioning=$state"

# Azure rejects stop/start while another long-running operation is in flight,
# and the resulting failure is opaque. Fail early with something readable.
if ($state -ne "Succeeded") {
    throw "Cluster '$ClusterName' is in provisioning state '$state', not 'Succeeded'. Refusing to $Action -- another operation is probably still running. No change made."
}

# Idempotency. Schedules can double-fire, and a missed night run must not turn
# the morning run into a no-op or vice versa.
if ($Action -eq "Stop" -and $power -eq "Stopped") {
    Write-Output "Cluster is already Stopped. Nothing to do."
    return
}
if ($Action -eq "Start" -and $power -eq "Running") {
    Write-Output "Cluster is already Running. Nothing to do."
    return
}

if ($Action -eq "Stop") {
    Write-Output "Stopping cluster (deallocates all node VMs and the control plane; no pod eviction, so PDBs are not involved)..."
    Stop-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName | Out-Null
}
else {
    Write-Output "Starting cluster (node pools return to their previous counts)..."
    Start-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName | Out-Null
}

$after = Get-AzAksCluster -ResourceGroupName $ResourceGroup -Name $ClusterName
Write-Output "AFTER: power=$($after.PowerState.Code) provisioning=$($after.ProvisioningState)"

# A start returns before workloads are ready. Pods, and Argo CD reconciliation,
# continue for several more minutes after this runbook reports success.
if ($Action -eq "Start") {
    Write-Output "Note: nodes are provisioning. Workloads need several more minutes to become Ready."
}
Write-Output "Done."
