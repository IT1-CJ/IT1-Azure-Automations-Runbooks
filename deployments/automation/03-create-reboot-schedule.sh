#!/bin/bash
# =============================================================================
# 03-create-reboot-schedule.sh
# 1. Imports required Az modules into the Automation Account
# 2. Creates a weekly Wednesday 11pm schedule
# 3. Links the schedule to the Restart-ManagedVM runbook
#
# Safe to copy-paste directly into Azure Cloud Shell.
# Uses az rest (no extensions required)
# Run AFTER: 02-deploy-reboot-runbook.sh
# =============================================================================

# ---------------------------------------------------------------------------
# VARIABLES — update these before running
# ---------------------------------------------------------------------------
SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="<your-resource-group>"
AUTOMATION_ACCOUNT="<your-automation-account-name>"

VM_NAME="<your-vm-name>"
VM_RESOURCE_GROUP="<your-resource-group>"   # RG where the VM lives (often same as above)

SCHEDULE_NAME="Weekly-Wednesday-11pm"
RUNBOOK_NAME="Restart-ManagedVM"

# Timezone — use IANA format. Common options:
#   UTC | America/New_York | America/Chicago | America/Denver | America/Los_Angeles
TIMEZONE="America/New_York"

API="2023-11-01"
# ---------------------------------------------------------------------------

set -euo pipefail

echo "==> Setting active subscription..."
az account set --subscription "$SUBSCRIPTION_ID"
echo "    OK"

# ---------------------------------------------------------------------------
# STEP 1 — Import Az.Accounts
# ---------------------------------------------------------------------------
echo ""
echo "==> [1/5] Importing Az.Accounts module..."
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/modules/Az.Accounts?api-version=${API}" \
  --body '{
    "properties": {
      "contentLink": {
        "uri": "https://www.powershellgallery.com/api/v2/package/Az.Accounts"
      }
    }
  }' \
  --output none
echo "    Import started — waiting for Az.Accounts to be ready..."

for i in $(seq 1 24); do
  STATUS=$(az rest --method GET \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/modules/Az.Accounts?api-version=${API}" \
    --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Pending")
  echo "    [$i/24] Az.Accounts: $STATUS"
  if [[ "$STATUS" == "Succeeded" ]]; then break; fi
  if [[ "$STATUS" == "Failed" ]]; then
    echo "ERROR: Az.Accounts import failed."
    exit 1
  fi
  sleep 15
done

if [[ "$STATUS" != "Succeeded" ]]; then
  echo "ERROR: Az.Accounts did not finish importing in time. Check the portal and re-run."
  exit 1
fi
echo "    Az.Accounts ready."

# ---------------------------------------------------------------------------
# STEP 2 — Import Az.Compute (depends on Az.Accounts being ready first)
# ---------------------------------------------------------------------------
echo ""
echo "==> [2/5] Importing Az.Compute module..."
az rest --method PUT \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/modules/Az.Compute?api-version=${API}" \
  --body '{
    "properties": {
      "contentLink": {
        "uri": "https://www.powershellgallery.com/api/v2/package/Az.Compute"
      }
    }
  }' \
  --output none
echo "    Import started — waiting for Az.Compute to be ready..."

for i in $(seq 1 24); do
  STATUS=$(az rest --method GET \
    --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/modules/Az.Compute?api-version=${API}" \
    --query "properties.provisioningState" -o tsv 2>/dev/null || echo "Pending")
  echo "    [$i/24] Az.Compute: $STATUS"
  if [[ "$STATUS" == "Succeeded" ]]; then break; fi
  if [[ "$STATUS" == "Failed" ]]; then
    echo "ERROR: Az.Compute import failed."
    exit 1
  fi
  sleep 15
done

if [[ "$STATUS" != "Succeeded" ]]; then
  echo "ERROR: Az.Compute did not finish importing in time. Check the portal and re-run."
  exit 1
fi
echo "    Az.Compute ready."

# ---------------------------------------------------------------------------
# STEP 3 — Calculate next Wednesday at 11pm
# ---------------------------------------------------------------------------
echo ""
echo "==> [3/5] Calculating next Wednesday 11pm schedule start time..."
DAY_OF_WEEK=$(date +%u)   # 1=Mon ... 7=Sun
TARGET_DAY=3              # Wednesday

if [ "$DAY_OF_WEEK" -lt "$TARGET_DAY" ]; then
  DAYS_AHEAD=$((TARGET_DAY - DAY_OF_WEEK))
elif [ "$DAY_OF_WEEK" -gt "$TARGET_DAY" ]; then
  DAYS_AHEAD=$((7 - DAY_OF_WEEK + TARGET_DAY))
else
  DAYS_AHEAD=7   # Today is Wednesday — schedule for next week
fi

START_DATE=$(date -d "+${DAYS_AHEAD} days" +"%Y-%m-%d")
START_TIME="${START_DATE}T23:00:00"
echo "    Schedule starts: $START_TIME ($TIMEZONE)"

# ---------------------------------------------------------------------------
# STEP 4 — Create the schedule
# ---------------------------------------------------------------------------
echo ""
echo "==> [4/5] Creating schedule: $SCHEDULE_NAME..."
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
      \"advancedSchedule\": {
        \"weekDays\": [\"Wednesday\"]
      }
    }
  }" \
  --output none
echo "    OK"

# ---------------------------------------------------------------------------
# STEP 5 — Link schedule to runbook
# ---------------------------------------------------------------------------
echo ""
echo "==> [5/5] Linking schedule to runbook with VM parameters..."
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

# ---------------------------------------------------------------------------
# VERIFICATION
# ---------------------------------------------------------------------------
echo ""
echo "============================================="
echo " VERIFICATION SUMMARY"
echo "============================================="

echo ""
echo "[1/3] Modules"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/modules?api-version=${API}" \
  --query "value[?name=='Az.Accounts' || name=='Az.Compute'].{Module:name, Status:properties.provisioningState}" \
  -o table

echo ""
echo "[2/3] Schedule"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/schedules/${SCHEDULE_NAME}?api-version=${API}" \
  --query "{Name:name, Frequency:properties.frequency, NextRun:properties.nextRun, TimeZone:properties.timeZone, Enabled:properties.isEnabled}" \
  -o table

echo ""
echo "[3/3] Job Schedule (runbook link)"
az rest --method GET \
  --url "https://management.azure.com/subscriptions/${SUBSCRIPTION_ID}/resourceGroups/${RESOURCE_GROUP}/providers/Microsoft.Automation/automationAccounts/${AUTOMATION_ACCOUNT}/jobSchedules?api-version=${API}" \
  --query "value[?properties.schedule.name=='${SCHEDULE_NAME}'].{Schedule:properties.schedule.name, Runbook:properties.runbook.name, VMName:properties.parameters.VMName}" \
  -o table

echo ""
echo "============================================="
echo " All done. VM '${VM_NAME}' will restart"
echo " every Wednesday at 11pm (${TIMEZONE})."
echo "============================================="
