#!/bin/bash
# =============================================================================
# 02-deploy-reboot-runbook.sh
# Uploads and publishes the Restart-ManagedVM PowerShell runbook.
# Self-contained — runbook content is embedded, no external files needed.
# Safe to copy-paste directly into Azure Cloud Shell.
#
# Uses az rest (no extensions required)
# Run AFTER: 01-create-automation-account.sh
# =============================================================================

# ---------------------------------------------------------------------------
# VARIABLES — must match values used in 01-create-automation-account.sh
# ---------------------------------------------------------------------------
SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="<your-resource-group>"
LOCATION="eastus"
AUTOMATION_ACCOUNT="<your-automation-account-name>"

RUNBOOK_NAME="Restart-ManagedVM"
RUNBOOK_DESCRIPTION="Restarts a single Azure VM by name using the Automation Account managed identity."

API="2023-11-01"
# ---------------------------------------------------------------------------

set -euo pipefail

echo "==> Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"
echo "    OK"

# ---------------------------------------------------------------------------
echo "==> Writing runbook content to temp file..."
TEMP_PS1=$(mktemp /tmp/runbook_XXXXXX.ps1)

cat > "$TEMP_PS1" << 'PSEOF'
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

Write-Output "Authenticating with managed identity..."
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    Write-Output "Authentication successful."
}
catch {
    Write-Error "Failed to authenticate with managed identity: $_"
    throw
}

Write-Output "Looking up VM '$VMName' in resource group '$ResourceGroupName'..."
$vm = Get-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction SilentlyContinue

if (-not $vm) {
    Write-Error "VM '$VMName' not found in resource group '$ResourceGroupName'."
    throw "VM not found."
}

Write-Output "Found VM: $($vm.Name) | Location: $($vm.Location) | Size: $($vm.HardwareProfile.VmSize)"

Write-Output "Restarting VM '$VMName'..."
try {
    Restart-AzVM -ResourceGroupName $ResourceGroupName -Name $VMName -ErrorAction Stop | Out-Null
    Write-Output "VM '$VMName' restarted successfully."
}
catch {
    Write-Error "Failed to restart VM '$VMName': $_"
    throw
}
PSEOF

echo "    Temp file: $TEMP_PS1"

# ---------------------------------------------------------------------------
echo "==> Creating runbook definition..."
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}?api-version=${API}" \
  --body "{
    \"location\": \"${LOCATION}\",
    \"properties\": {
      \"runbookType\": \"PowerShell\",
      \"description\": \"${RUNBOOK_DESCRIPTION}\",
      \"logProgress\": true,
      \"logVerbose\": false
    }
  }" \
  --output none
echo "    OK"

# ---------------------------------------------------------------------------
echo "==> Uploading runbook content..."
ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: text/powershell" \
  --data-binary @"${TEMP_PS1}" \
  "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}/draft/content?api-version=${API}")

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "202" ]]; then
  echo "ERROR: Failed to upload runbook content (HTTP $HTTP_STATUS)"
  rm -f "$TEMP_PS1"
  exit 1
fi
echo "    OK (HTTP $HTTP_STATUS)"

# ---------------------------------------------------------------------------
echo "==> Publishing runbook..."
az rest --method POST \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}/publish?api-version=${API}" \
  --output none
echo "    OK"

# ---------------------------------------------------------------------------
echo "==> Cleaning up temp file..."
rm -f "$TEMP_PS1"
echo "    OK"

# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " VERIFICATION SUMMARY"
echo "============================================="

echo ""
echo "[1/1] Runbook Status"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}?api-version=${API}" \
  --query "{Name:name, Type:properties.runbookType, State:properties.state}" \
  -o table

echo ""
echo "============================================="
echo " Runbook deployed and published successfully."
echo ""
echo " To trigger a VM restart manually:"
echo ""
echo "   az rest --method POST \\"
echo "     --url 'https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/jobs?api-version=${API}' \\"
echo "     --body '{\"properties\": {\"runbook\": {\"name\": \"${RUNBOOK_NAME}\"}, \"parameters\": {\"VMName\": \"<vm-name>\", \"ResourceGroupName\": \"<vm-rg>\"}}}'"
echo "============================================="
