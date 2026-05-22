#!/bin/bash
# =============================================================================
# deploy.sh — Full Azure Automation deployment
# Runs all 3 steps in sequence:
#   1. Create Automation Account + managed identity
#   2. Deploy Restart-ManagedVM runbook
#   3. Import modules + create Wednesday 11pm reboot schedule
#
# USAGE:
#   1. Edit config.env with customer values
#   2. chmod +x deploy.sh && ./deploy.sh
#
# Safe to copy-paste into Azure Cloud Shell. No extensions required.
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Load config
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG="$SCRIPT_DIR/config.env"

if [[ ! -f "$CONFIG" ]]; then
  echo "ERROR: config.env not found at $CONFIG"
  exit 1
fi

source "$CONFIG"

API="2023-11-01"
RUNBOOK_NAME="Restart-ManagedVM"
SCHEDULE_NAME="Weekly-Wednesday-11pm"

# ---------------------------------------------------------------------------
# Validate config — make sure placeholders were replaced
# ---------------------------------------------------------------------------
for VAR in SUBSCRIPTION_ID RESOURCE_GROUP LOCATION AUTOMATION_ACCOUNT VM_NAME VM_RESOURCE_GROUP TIMEZONE; do
  VALUE="${!VAR}"
  if [[ "$VALUE" == "<"* ]]; then
    echo "ERROR: $VAR is still a placeholder in config.env. Please fill it in."
    exit 1
  fi
done

# ---------------------------------------------------------------------------
# Auto-detect timezone from Azure region
# ---------------------------------------------------------------------------
detect_timezone() {
  local REGION="$1"
  case "$REGION" in
    # United States
    eastus|eastus2)                   echo "America/New_York" ;;
    northcentralus|southcentralus)    echo "America/Chicago" ;;
    centralus|westcentralus)          echo "America/Chicago" ;;
    westus|westus2|westus3)           echo "America/Los_Angeles" ;;
    # Canada
    canadacentral)                    echo "America/Toronto" ;;
    canadaeast)                       echo "America/Halifax" ;;
    # Europe
    uksouth|ukwest)                   echo "Europe/London" ;;
    northeurope)                      echo "Europe/Dublin" ;;
    westeurope)                       echo "Europe/Amsterdam" ;;
    germanywestcentral)               echo "Europe/Berlin" ;;
    francecentral|francesouth)        echo "Europe/Paris" ;;
    switzerlandnorth|switzerlandwest) echo "Europe/Zurich" ;;
    norwayeast|norwaywest)            echo "Europe/Oslo" ;;
    swedencentral)                    echo "Europe/Stockholm" ;;
    polandcentral)                    echo "Europe/Warsaw" ;;
    italynorth)                       echo "Europe/Rome" ;;
    spaincentral)                     echo "Europe/Madrid" ;;
    # Asia Pacific
    eastasia)                         echo "Asia/Hong_Kong" ;;
    southeastasia)                    echo "Asia/Singapore" ;;
    japaneast|japanwest)              echo "Asia/Tokyo" ;;
    koreacentral|koreasouth)          echo "Asia/Seoul" ;;
    centralindia|southindia|westindia|jioindiawest|jioindiacentral) echo "Asia/Kolkata" ;;
    australiaeast|australiasoutheast) echo "Australia/Sydney" ;;
    australiacentral|australiacentral2) echo "Australia/Darwin" ;;
    newzealandnorth)                  echo "Pacific/Auckland" ;;
    # Middle East & Africa
    uaenorth|uaecentral)              echo "Asia/Dubai" ;;
    southafricanorth|southafricawest) echo "Africa/Johannesburg" ;;
    israelcentral)                    echo "Asia/Jerusalem" ;;
    qatarcentral)                     echo "Asia/Qatar" ;;
    # South America
    brazilsouth|brazilsoutheast)      echo "America/Sao_Paulo" ;;
    # Fallback
    *)                                echo "" ;;
  esac
}

if [[ "$TIMEZONE" == "auto" ]]; then
  echo "==> Detecting timezone from region: $LOCATION..."
  DETECTED_TZ=$(detect_timezone "$LOCATION")
  if [[ -n "$DETECTED_TZ" ]]; then
    TIMEZONE="$DETECTED_TZ"
    echo "    Detected: $TIMEZONE"
  else
    echo "    WARNING: Region '$LOCATION' not recognized. Defaulting to UTC."
    echo "    You can set TIMEZONE manually in config.env."
    TIMEZONE="UTC"
  fi
fi

echo ""
echo "============================================="
echo " DEPLOYMENT CONFIG"
echo "============================================="
echo "  Subscription   : $SUBSCRIPTION_ID"
echo "  Resource Group : $RESOURCE_GROUP"
echo "  Location       : $LOCATION"
echo "  Automation Acct: $AUTOMATION_ACCOUNT"
echo "  VM Name        : $VM_NAME"
echo "  VM RG          : $VM_RESOURCE_GROUP"
echo "  Timezone       : $TIMEZONE"
echo "============================================="
echo ""
read -rp "Looks good? Press Enter to continue or Ctrl+C to cancel..."
echo ""

# ---------------------------------------------------------------------------
# STEP 1 — Create Automation Account
# ---------------------------------------------------------------------------
echo "============================================="
echo " STEP 1 of 3 — Automation Account"
echo "============================================="

echo "==> Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"
echo "    OK"

echo "==> Creating resource group (if it does not exist)..."
az group create \
  --name "$RESOURCE_GROUP" \
  --location "$LOCATION" \
  --output none
echo "    OK"

echo "==> Creating Automation Account with system-assigned managed identity..."
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}?api-version=${API}" \
  --body "{
    \"location\": \"${LOCATION}\",
    \"identity\": { \"type\": \"SystemAssigned\" },
    \"properties\": { \"sku\": { \"name\": \"Basic\" } }
  }" \
  --output none
echo "    OK"

echo "==> Retrieving managed identity Principal ID..."
sleep 10
PRINCIPAL_ID=$(az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}?api-version=${API}" \
  --query "identity.principalId" --output tsv)

if [[ -z "$PRINCIPAL_ID" ]]; then
  echo "ERROR: Could not retrieve Principal ID."
  exit 1
fi
echo "    Principal ID: $PRINCIPAL_ID"

echo "==> Assigning 'Virtual Machine Contributor' to the managed identity..."
RG_SCOPE=$(az group show --name "$RESOURCE_GROUP" --query "id" --output tsv)
az role assignment create \
  --assignee "$PRINCIPAL_ID" \
  --role "Virtual Machine Contributor" \
  --scope "$RG_SCOPE" \
  --output none
echo "    OK"
echo ""
echo "✓ Step 1 complete."
echo ""

# ---------------------------------------------------------------------------
# STEP 2 — Deploy Runbook
# ---------------------------------------------------------------------------
echo "============================================="
echo " STEP 2 of 3 — Deploy Runbook"
echo "============================================="

echo "==> Creating runbook definition..."
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}?api-version=${API}" \
  --body "{
    \"location\": \"${LOCATION}\",
    \"properties\": {
      \"runbookType\": \"PowerShell\",
      \"description\": \"Restarts a single Azure VM by name using the Automation Account managed identity.\",
      \"logProgress\": true,
      \"logVerbose\": false
    }
  }" \
  --output none
echo "    OK"

echo "==> Writing runbook content to temp file..."
TEMP_PS1=$(mktemp /tmp/runbook_XXXXXX.ps1)
cat > "$TEMP_PS1" << 'PSEOF'
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

echo "==> Uploading runbook content..."
ACCESS_TOKEN=$(az account get-access-token --query accessToken -o tsv)
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" -X PUT \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  -H "Content-Type: text/powershell" \
  --data-binary @"${TEMP_PS1}" \
  "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}/draft/content?api-version=${API}")

rm -f "$TEMP_PS1"

if [[ "$HTTP_STATUS" != "200" && "$HTTP_STATUS" != "202" ]]; then
  echo "ERROR: Failed to upload runbook content (HTTP $HTTP_STATUS)"
  exit 1
fi
echo "    OK (HTTP $HTTP_STATUS)"

echo "==> Publishing runbook..."
az rest --method POST \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}/publish?api-version=${API}" \
  --output none
echo "    OK"
echo ""
echo "✓ Step 2 complete."
echo ""

# ---------------------------------------------------------------------------
# STEP 3 — Import Modules + Create Schedule
# ---------------------------------------------------------------------------
echo "============================================="
echo " STEP 3 of 3 — Modules + Schedule"
echo "============================================="

import_module() {
  local MODULE=$1
  echo "==> Importing $MODULE..."
  az rest --method PUT \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/modules/${MODULE}?api-version=${API}" \
    --body "{
      \"properties\": {
        \"contentLink\": {
          \"uri\": \"https://www.powershellgallery.com/api/v2/package/${MODULE}\"
        }
      }
    }" \
    --output none

  for i in $(seq 1 24); do
    STATUS=$(az rest --method GET \
      --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/modules/${MODULE}?api-version=${API}" \
      --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Pending")
    echo "    [$i/24] $MODULE: $STATUS"
    if [[ "$STATUS" == "Succeeded" ]]; then return 0; fi
    if [[ "$STATUS" == "Failed" ]]; then echo "ERROR: $MODULE import failed."; exit 1; fi
    sleep 15
  done
  echo "ERROR: $MODULE did not finish in time."
  exit 1
}

import_module "Az.Accounts"
import_module "Az.Compute"

echo "==> Calculating next Wednesday 11pm..."
DAY_OF_WEEK=$(date +%u)
TARGET_DAY=3
if [ "$DAY_OF_WEEK" -lt "$TARGET_DAY" ]; then
  DAYS_AHEAD=$((TARGET_DAY - DAY_OF_WEEK))
elif [ "$DAY_OF_WEEK" -gt "$TARGET_DAY" ]; then
  DAYS_AHEAD=$((7 - DAY_OF_WEEK + TARGET_DAY))
else
  DAYS_AHEAD=7
fi
START_TIME="$(date -d "+${DAYS_AHEAD} days" +"%Y-%m-%d")T23:00:00"
echo "    Starts: $START_TIME ($TIMEZONE)"

echo "==> Creating schedule..."
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/schedules/${SCHEDULE_NAME}?api-version=${API}" \
  --body "{
    \"name\": \"${SCHEDULE_NAME}\",
    \"properties\": {
      \"description\": \"Weekly reboot every Wednesday at 11pm\",
      \"startTime\": \"${START_TIME}\",
      \"frequency\": \"Week\",
      \"interval\": 1,
      \"timeZone\": \"${TIMEZONE}\",
      \"advancedSchedule\": { \"weekDays\": [\"Wednesday\"] }
    }
  }" \
  --output none
echo "    OK"

echo "==> Linking schedule to runbook..."
JOB_SCHEDULE_ID=$(cat /proc/sys/kernel/random/uuid)
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/jobSchedules/${JOB_SCHEDULE_ID}?api-version=${API}" \
  --body "{
    \"properties\": {
      \"schedule\": { \"name\": \"${SCHEDULE_NAME}\" },
      \"runbook\": { \"name\": \"${RUNBOOK_NAME}\" },
      \"parameters\": {
        \"VMName\": \"${VM_NAME}\",
        \"ResourceGroupName\": \"${VM_RESOURCE_GROUP}\"
      }
    }
  }" \
  --output none
echo "    OK"
echo ""
echo "✓ Step 3 complete."

# ---------------------------------------------------------------------------
# FINAL VERIFICATION
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " FINAL VERIFICATION"
echo "============================================="

echo ""
echo "[1/4] Automation Account"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}?api-version=${API}" \
  --query "{Name:name, State:properties.state, Identity:identity.type}" \
  -o table

echo ""
echo "[2/4] Role Assignment"
az role assignment list \
  --assignee "$PRINCIPAL_ID" \
  --role "Virtual Machine Contributor" \
  --scope "$RG_SCOPE" \
  --query "[].{Role:roleDefinitionName, AssignedTo:principalId}" \
  -o table

echo ""
echo "[3/4] Runbook"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/runbooks/${RUNBOOK_NAME}?api-version=${API}" \
  --query "{Name:name, Type:properties.runbookType, State:properties.state}" \
  -o table

echo ""
echo "[4/4] Schedule"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/schedules/${SCHEDULE_NAME}?api-version=${API}" \
  --query "{Name:name, NextRun:properties.nextRun, Enabled:properties.isEnabled, Timezone:properties.timeZone}" \
  -o table

echo ""
echo "============================================="
echo " ALL DONE"
echo " VM '${VM_NAME}' will reboot every Wednesday"
echo " at 11pm (${TIMEZONE})."
echo "============================================="
