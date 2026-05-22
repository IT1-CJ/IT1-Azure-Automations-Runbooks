<#
.SYNOPSIS
    Restarts a single Azure VM by name.

.DESCRIPTION
    Uses the Automation Account system-assigned managed identity to authenticate
    and restart a specified VM. Intended to be triggered by Azure Update Manager
    post-patching or called manually via the Automation Account.

.PARAMETER VMName
    The name of the VM to restart.

.PARAMETER ResourceGroupName
    The resource group that contains the VM.

.NOTES
    Authentication : System-assigned managed identity (no stored credentials)
    Runbook Type   : PowerShell
    Requires       : Az.Accounts, Az.Compute modules in the Automation Account
#>

param (
    [Parameter(Mandatory = $true)]
    [string] $VMName,

    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName
)

# ---------------------------------------------------------------------------
# Authenticate using the Automation Account managed identity
# ---------------------------------------------------------------------------
Write-Output "Authenticating with managed identity..."

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-Output "Authentication successful."
}
catch {
    Write-Error "Failed to authenticate with managed identity: $_"
    throw
}

# ---------------------------------------------------------------------------
# Validate the VM exists
# ---------------------------------------------------------------------------
Write-Output "Looking up VM '$VMName' in resource group '$ResourceGroupName'..."

$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue

if (-not $vm) {
    Write-Error "VM '$VMName' not found in resource group '$ResourceGroupName'."
    throw "VM not found."
}

Write-Output "Found VM: $($vm.Name) | Location: $($vm.Location) | Size: $($vm.HardwareProfile.VmSize)"

# ---------------------------------------------------------------------------
# Restart the VM
# ---------------------------------------------------------------------------
Write-Output "Restarting VM '$VMName'..."

try {
    Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop | Out-Null
    Write-Output "✓ VM '$VMName' restarted successfully."
}
catch {
    Write-Error "Failed to restart VM '$VMName': $_"
    throw
}
