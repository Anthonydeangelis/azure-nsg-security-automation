# NSG-change Logic App

> These notes describe the earlier checked-in workflow example, not the final live
> workflow. The deployed lab later added a 30-minute delay and managed-identity
> HTTP call. See [the current build guide](../docs/deployment.md). Do not apply an
> older empty `actions` object over the live workflow or combine duplicate resource
> definitions from this snippets directory.

## Current stage

`Logic_App.tf` passes three deployment parameters to
`templates/nsg-change.logic-app.json`. The template manages the existing
Consumption workflow named `NSG-change`, including its Sentinel alert trigger.
There are no actions yet: no delay and no Function call.

These files are snippets for the existing lab's Terraform configuration, like
the other files in this folder. This directory has no standalone provider,
backend or variable configuration. Copy the template directory together with
the Terraform file when incorporating it into the owning configuration.

## Parameter flow

| Terraform value | ARM parameter | Used for |
| --- | --- | --- |
| `var.nsg_workflow_name` | `workflowName` | Existing Logic App's resource name |
| `var.location` | `location` | Workflow region and Sentinel connector API region |
| `var.nsg_sentinel_connection_name` | `sentinelConnectionName` | Existing API connection's name and resource ID |

The deployment uses the subscription selected by the AzureRM provider and the
resource group passed as `var.rg-lab`. ARM's `resourceId()` constructs the
connection ID in that deployment's resource group. `subscriptionResourceId()`
constructs the regional managed API ID. No real subscription ID is embedded.

For the existing app, verify that `var.location` is `eastus2` and that
`azuresentinel-1` is an existing managed-identity-compatible connection there.
This template references the connection; it does not create or change it.
If the connection lives in another resource group, change the input contract
to accept its full resource ID rather than using the current `resourceId()`.

`$connections` is a workflow parameter, distinct from ARM deployment parameters.
It supplies the connector resource and managed identity authentication to the
trigger. The `azuresentinel-1` key in that object is an internal alias: it must
match the trigger's expression, even if the actual connection name changes.

## How the correct alert launches the workflow

The trigger contains no analytics-rule filter. `NSG_Automation.tf` defines
the automation rule that provides the routing:

1. Trigger on alert creation.
2. Match the analytics rule `NSG-config-change`, identified by rule ID
   `6bda0e6e-ffa6-47c7-b5de-36cfd9977c86`.
3. Run the `NSG-change` playbook.
4. Sentinel supplies the alert payload to the workflow trigger.

The automation condition uses `AlertAnalyticRuleIds`, `Contains`, and the full
Terraform resource ID of the existing analytics rule. It matches rule identity,
not the generated alert title, which is customized to include the NSG name.
The playbook action gets its workflow ID from the ARM deployment output, so
Terraform waits for the workflow deployment before creating the automation rule.
The rule's UUID is generated deterministically with Terraform's `uuidv5()`.
The outer order controls automation-rule ordering; the action's order controls
the sequence of actions within this one rule.

## Permission to execute the playbook

Before deploying the automation rule, inspect IAM on the playbook resource group.
Sentinel's Azure Security Insights service identity needs Microsoft Sentinel
Automation Contributor there. This is a different identity and role from the
Logic App's own Sentinel Reader assignment. Since the lab already has an email
playbook, this resource-group permission may already exist. Reuse it if present.
The local snippets do not invent an object ID or create a duplicate assignment.
If the grant is missing, identify the tenant's service principal and manage that
single assignment in the owning lab configuration (or use Sentinel Automation's
Manage playbook permissions). If already managed elsewhere, keep that owner.

## First integration test

Review the combined plan in the existing lab. After deployment and permission
verification, make one new change to the unattached demo NSG rule. A newly
generated NSG-config-change alert should start a run in NSG-change. Existing
alerts are not replayed by creating the automation rule. Inspect trigger inputs
to confirm the alert and resource identifiers arrived. With no actions yet,
the workflow should finish immediately; the delay and checker come next.

The Logic App identity's Sentinel Reader assignment is separate. It was
reported as added in the portal; this template does not manage that assignment.
Represent it in the owning Terraform configuration after checking existing
role assignments and import any existing assignment rather than duplicating it.

## Ownership and verification

Keep the current workflow name and region to update the portal-created app.
Use only one Terraform owner for its definition. Do not combine this deployment
with separate workflow, action or trigger resources targeting the same app.

This template was cleaned from the supplied export: generated endpoint IP lists
and the accessKeys child resource were removed. ARM JSON syntax is checked
locally; Azure deployment validation and a full Terraform plan are still needed
in the owning lab configuration.

An incremental deployment still updates the entire workflow definition. Once
new actions are added in the portal, export and merge them into this template
before deploying again, or the currently empty `actions` object will remove them.

Review the plan in the owning configuration. Terraform may show the ARM deployment
resource as new even when the nested Logic App already exists; inspect the ARM
template/what-if as well to review nested resource effects. Do not delete the
portal app just to bring it under this deployment.
