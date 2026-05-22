#!/bin/bash
# =============================================================================
# 01-create-automation-account.sh
# Creates an Azure Automation Account with a system-assigned managed identity
# and grants it VM Contributor rights on the target resource group.
#
# Run BEFORE: 02-deploy-reboot-runbook.sh
# =============================================================================

# ---------------------------------------------------------------------------
# VARIABLES — update these before running
# ---------------------------------------------------------------------------
SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="<your-resource-group>"
LOCATION="eastus"                          # e.g. eastus, westus2, uksouth
AUTOMATION_ACCOUNT="<your-automation-account-name>"

# Role to assign to the Automation Account managed identity
# "Virtual Machine Contributor" allows Start/Stop/Restart but not full control
ROLE="Virtual Machine Contributor"
# ---------------------------------------------------------------------------

set -euo pipefail

echo "==> Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"

echo "==> Creating resource group (if it does not exist)..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none

echo "==> Creating Automation Account: $AUTOMATION_ACCOUNT..."
az automation account create \
  --name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --sku "Basic" \
  --output none

echo "==> Enabling system-assigned managed identity..."
PRINCIPAL_ID=$(az automation account update \
  --name "$AUTOMATION_ACCOUNT" \
  --resource-group "$RESOURCE_GROUP" \
  --assign-identity "[system]" \
  --query "identity.principalId" \
  --output tsv)

echo "    Principal ID: $PRINCIPAL_ID"

echo "==> Retrieving resource group scope..."
RG_SCOPE=$(az group show \
  --name "$RESOURCE_GROUP" \
  --query "id" \
  --output tsv)

echo "==> Assigning '$ROLE' to the managed identity..."
az role assignment create \
  --assignee "$PRINCIPAL_ID" \
  --role "$ROLE" \
  --scope "$RG_SCOPE" \
  --output none

echo ""
echo "✓ Automation Account '$AUTOMATION_ACCOUNT' created successfully."
echo "  Resource Group : $RESOURCE_GROUP"
echo "  Location       : $LOCATION"
echo "  Identity       : $PRINCIPAL_ID"
echo ""
echo "Next step: run 02-deploy-reboot-runbook.sh"
