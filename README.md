# IT1 Azure Automation Runbooks

Repeatable deployment scripts and PowerShell runbooks for Azure Automation.

## Concepts

| Term | Tool | What it does |
|------|------|-------------|
| **Patching** | Azure Update Manager | Installs OS updates on VMs |
| **Reboot** | Azure Automation Runbook | Restarts a VM after patching |

---

## Deployments

### `deployments/automation/` — VM Reboot Runbook

```
deployments/automation/
├── 01-create-automation-account.sh   # Creates Automation Account + managed identity
├── 02-deploy-reboot-runbook.sh       # Uploads and publishes the runbook (self-contained)
├── 03-create-reboot-schedule.sh      # Imports modules + creates Wednesday 11pm schedule
└── runbook-source/
    └── Restart-ManagedVM.ps1         # PowerShell runbook — restarts a VM by name
```

#### Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and logged in (`az login`)
- `Az.Accounts` and `Az.Compute` modules imported in the Automation Account
- Contributor or Owner rights on the target subscription/resource group

#### Deployment steps

**1. Set your variables**

Open each script and fill in the variables block at the top:

```bash
SUBSCRIPTION_ID="<your-subscription-id>"
RESOURCE_GROUP="<your-resource-group>"
LOCATION="eastus"
AUTOMATION_ACCOUNT="<your-automation-account-name>"
```

**2. Create the Automation Account**

```bash
chmod +x deployments/automation/01-create-automation-account.sh
./deployments/automation/01-create-automation-account.sh
```

This creates the Automation Account with a system-assigned managed identity and grants it **Virtual Machine Contributor** on the resource group.

**3. Deploy the runbook**

```bash
chmod +x deployments/automation/02-deploy-reboot-runbook.sh
./deployments/automation/02-deploy-reboot-runbook.sh
```

This uploads and publishes `Restart-ManagedVM.ps1` to the Automation Account.

**4. Create the schedule**

```bash
chmod +x deployments/automation/03-create-reboot-schedule.sh
./deployments/automation/03-create-reboot-schedule.sh
```

This imports `Az.Accounts` and `Az.Compute` modules, creates a weekly Wednesday 11pm schedule, and links it to the runbook with your VM as the target.

#### Trigger a reboot manually

```bash
az automation runbook start \
  --name Restart-ManagedVM \
  --resource-group <your-resource-group> \
  --automation-account-name <your-automation-account-name> \
  --parameters VMName=<vm-name> ResourceGroupName=<vm-resource-group>
```

---

## References

- [Azure Automation documentation](https://learn.microsoft.com/en-us/azure/automation/)
- [Azure Update Manager documentation](https://learn.microsoft.com/en-us/azure/update-manager/)
- [Managed identities for Automation](https://learn.microsoft.com/en-us/azure/automation/enable-managed-identity-for-automation)
