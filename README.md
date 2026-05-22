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
├── config.env    ← Edit this with customer values (one file, one time)
├── deploy.sh     ← Run this — does everything in sequence
│
│   (individual steps — kept for reference or re-running a single step)
├── 01-create-automation-account.sh
├── 02-deploy-reboot-runbook.sh
├── 03-create-reboot-schedule.sh
└── runbook-source/
    └── Restart-ManagedVM.ps1
```

#### Prerequisites

- [Azure CLI](https://learn.microsoft.com/en-us/cli/azure/install-azure-cli) installed and logged in (`az login`)
- `Az.Accounts` and `Az.Compute` modules imported in the Automation Account
- Contributor or Owner rights on the target subscription/resource group

#### Deployment steps

**1. Clone and navigate**

```bash
git clone https://github.com/IT1-CJ/IT1-Azure-Automations-Runbooks.git
cd IT1-Azure-Automations-Runbooks/deployments/automation
```

**2. Edit config.env — the only file you touch**

```bash
nano config.env
```

Fill in your 7 values, save with Ctrl+O → Enter → Ctrl+X.

**3. Run deploy.sh — does everything**

```bash
chmod +x deploy.sh && ./deploy.sh
```

That's it. The script runs all 3 steps in sequence, shows progress, and prints a final verification summary.

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
