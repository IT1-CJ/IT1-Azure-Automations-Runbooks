#!/bin/bash
# =============================================================================
# 01-create-automation-account.sh
# Creates an Azure Automation Account with a system-assigned managed identity
# and grants it VM Contributor rights on the target resource group.
#
# Uses az rest (no extensions required — safe for Azure Cloud Shell)
# Run BEFORE: 02-deploy-reboot-runbook.sh
# =============================================================================

# ---------------------------------------------------------------------------
# VARIABLES — update these before running
# ---------------------------------------------------------------------------
SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="<your-resource-group>"
LOCATION="eastus"                          # e.g. eastus, westus2, uksouth
AUTOMATION_ACCOUNT="<your-automation-account-name>"

ROLE="Virtual Machine Contributor"
API="2023-11-01"
# ---------------------------------------------------------------------------

set -euo pipefail

echo "==> Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"
echo "    OK"

# ---------------------------------------------------------------------------
echo "==> Creating resource group (if it does not exist)..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none
echo "    OK"

# ---------------------------------------------------------------------------
echo "==> Creating Automation Account with system-assigned managed identity..."
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}?api-version=${API}" \
  --body "{
    \"location\": \"${LOCATION}\",
    \"identity\": {
      \"type\": \"SystemAssigned\"
    },
    \"properties\": {
      \"sku\": { \"name\": \"Basic\" }
    }
  }" \
  --output none
echo "    OK"

# ---------------------------------------------------------------------------
echo "==> Retrieving managed identity Principal ID (waiting for propagation)..."
sleep 10
PRINCIPAL_ID=$(az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}?api-version=${API}" \
  --query "identity.principalId" \
  --output tsv)

if [[ -z "$PRINCIPAL_ID" ]]; then
  echo "ERROR: Could not retrieve Principal ID. Check the Automation Account was created."
  exit 1
fi
echo "    Principal ID: $PRINCIPAL_ID"

# ---------------------------------------------------------------------------
echo "==> Retrieving resource group scope..."
RG_SCOPE=$(az group show \
  --name "$RESOURCE_GROUP" \
  --query "id" \
  --output tsv)
echo "    Scope: $RG_SCOPE"

# ---------------------------------------------------------------------------
echo "==> Assigning '$ROLE' to the managed identity..."
az role assignment create \
  --assignee "$PRINCIPAL_ID" \
  --role "$ROLE" \
  --scope "$RG_SCOPE" \
  --output none
echo "    OK"

# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " VERIFICATION SUMMARY"
echo "============================================="

echo ""
echo "[1/3] Resource Group"
az group show \
  --name "$RESOURCE_GROUP" \
  --query "{Name:name, Location:location, State:properties.provisioningState}" \
  -o table

echo ""
echo "[2/3] Automation Account"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}?api-version=${API}" \
  --query "{Name:name, Location:location, SKU:sku.name, Identity:identity.type, State:properties.state}" \
  -o table

echo ""
echo "[3/3] Role Assignment"
az role assignment list \
  --assignee "$PRINCIPAL_ID" \
  --role "$ROLE" \
  --scope "$RG_SCOPE" \
  --query "[].{Role:roleDefinitionName, AssignedTo:principalId}" \
  -o table

echo ""
echo "============================================="
echo " All steps complete."
echo " Next: run 02-deploy-reboot-runbook.sh"
echo "============================================="
