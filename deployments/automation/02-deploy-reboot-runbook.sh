#!/bin/bash
# =============================================================================
# 02-deploy-reboot-runbook.sh
# Uploads and publishes the Restart-ManagedVM PowerShell runbook to an
# existing Azure Automation Account.
#
# Uses az rest (no extensions required — safe for Azure Cloud Shell)
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
RUNBOOK_SOURCE="./runbook-source/Restart-ManagedVM.ps1"

API="2023-11-01"
# ---------------------------------------------------------------------------

set -euo pipefail

echo "==> Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"
echo "    OK"

# ---------------------------------------------------------------------------
echo "==> Checking runbook source file exists..."
if [[ ! -f "$RUNBOOK_SOURCE" ]]; then
  echo "ERROR: Runbook source not found at: $RUNBOOK_SOURCE"
  echo "       Make sure you are running this script from the 'deployments/automation' folder."
  exit 1
fi
echo "    Found: $RUNBOOK_SOURCE"

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
  --data-binary @"${RUNBOOK_SOURCE}" \
  "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}/draft/content?api-version=${API}")

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "202" ]]; then
  echo "ERROR: Failed to upload runbook content (HTTP $HTTP_STATUS)"
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
echo ""
echo "============================================="
echo " VERIFICATION SUMMARY"
echo "============================================="

echo ""
echo "[1/1] Runbook Status"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}?api-version=${API}" \
  --query "{Name:name, Type:properties.runbookType, State:properties.state, Description:properties.description}" \
  -o table

echo ""
echo "============================================="
echo " Runbook deployed and published successfully."
echo ""
echo " To trigger a VM restart:"
echo "   az rest --method POST \\"
echo "     --url \"https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}/start?api-version=${API}\" \\"
echo "     --body '{\"parameters\": {\"VMName\": \"<vm-name>\", \"ResourceGroupName\": \"<vm-rg>\"}}'"
echo "============================================="
