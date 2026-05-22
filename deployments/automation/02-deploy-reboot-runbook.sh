#!/bin/bash
# =============================================================================
# 02-deploy-reboot-runbook.sh
# Uploads and publishes the Restart-ManagedVM PowerShell runbook to an
# existing Azure Automation Account.
#
# Run AFTER: 01-create-automation-account.sh
# =============================================================================

# ---------------------------------------------------------------------------
# VARIABLES — must match values used in 01-create-automation-account.sh
# ---------------------------------------------------------------------------
SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="<your-resource-group>"
AUTOMATION_ACCOUNT="<your-automation-account-name>"

RUNBOOK_NAME="Restart-ManagedVM"
RUNBOOK_TYPE="PowerShell"
RUNBOOK_DESCRIPTION="Restarts a single Azure VM by name using the Automation Account managed identity."
RUNBOOK_SOURCE="./runbook-source/Restart-ManagedVM.ps1"
# ---------------------------------------------------------------------------

set -euo pipefail

echo "==> Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

echo "==> Checking runbook source file exists..."
if [[ ! -f "$RUNBOOK_SOURCE" ]]; then
  echo "ERROR: Runbook source not found at: $RUNBOOK_SOURCE"
  exit 1
fi

echo "==> Importing runbook: $RUNBOOK_NAME..."
az automation runbook create \
  --name "$RUNBOOK_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --type "$RUNBOOK_TYPE" \
  --description "$RUNBOOK_DESCRIPTION" \
  --output none

az automation runbook replace-content \
  --name "$RUNBOOK_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --content "@$RUNBOOK_SOURCE" \
  --output none

echo "==> Publishing runbook..."
az automation runbook publish \
  --name "$RUNBOOK_NAME" \
  --resource-group "$RESOURCE_GROUP" \
  --automation-account-name "$AUTOMATION_ACCOUNT" \
  --output none

echo ""
echo "✓ Runbook '$RUNBOOK_NAME' deployed and published successfully."
echo "  Automation Account : $AUTOMATION_ACCOUNT"
echo "  Resource Group     : $RESOURCE_GROUP"
echo ""
echo "To trigger a VM restart manually:"
echo "  az automation runbook start \\"
echo "    --name $RUNBOOK_NAME \\"
echo "    --resource-group $RESOURCE_GROUP \\"
echo "    --automation-account-name $AUTOMATION_ACCOUNT \\"
echo "    --parameters VMName=<vm-name> ResourceGroupName=<vm-resource-group>"
