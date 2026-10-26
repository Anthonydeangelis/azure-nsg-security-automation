# Build and deployment walkthrough

[Portfolio overview](../README.md) · [Architecture](architecture.md) · [Validation](validation.md)

This records the sequence used to build the lab. It is not a turnkey deployment.
Infrastructure was applied in the existing
[Azure-Infra-Security-Lab repository](https://github.com/Anthonydeangelis/Azure-Infra-Security-Lab),
not from this folder. Do not deploy a second owner for its existing resources.

## 1. Prerequisites and ownership

- An Azure subscription with the existing lab resource group, network, private web VM and management access.
- A Log Analytics workspace onboarded to Sentinel and subscription Activity Logs flowing to it.
- Permission to create project resources and separately assign the required roles.
- The owning infrastructure repo's provider versions, backend, variables, and reviewed plan/apply process.
- Azure CLI for local authentication, Functions Core Tools v4, and Python matching the Function runtime. The deployed lab used Python 3.14.
- A private SSH path to the web VM. The demonstrated VM used Ubuntu, Python 3.12 and Nginx 1.24.

The checked-in `Terraform/` snippets include duplicate workflow/automation
definitions across `Sentinal_rule.tf`, `Logic_App.tf`, and `NSG_Automation.tf`.
Some templates still have an empty `actions` object. These are learning artifacts,
not files to concatenate or a current deployment bundle. Use the owning lab's
final configuration and review nested ARM definitions before applying: an older
empty workflow definition can remove deployed actions.

## 2. Create the supporting infrastructure in the owning repo

Review the plan before each apply. The live project used:

1. A dedicated, unattached demo NSG. Do not test broad SSH rules on a real management path.
2. StorageV2 with LRS, TLS 1.2 minimum, public blob access disabled, and shared-key access disabled.
3. A private `function-deployments` blob container and `NsgFindings` table.
4. A user-assigned managed identity, assigned the documented Storage permissions before Function creation.
5. A Linux FC1 service plan and Python Flex Consumption Function App, using that identity for deployment storage and host storage.
6. An API app registration / Entra platform authentication configuration for the Function App.
7. A Consumption Logic App with system identity and the existing Sentinel connector.
8. A custom Analytics-plan `NsgFindings_CL` table, then a Direct DCR with matching stream schema and workspace destination.

Table creation initially hit a shared-key ACL operation in the provider path;
the table was subsequently managed via an ARM template deployment without
reenabling account keys. Existing state ownership was reconciled rather than
managing the same table twice. Do not copy a state-removal instruction into a
different environment without checking its current state.

Resource role assignments and API caller allowlists are different; see the
[identity matrix](architecture.md#identity-and-access-boundaries). The GitHub
principal had Contributor but not role-assignment rights, so the operator granted
roles separately. Function deployment does not automatically grant these roles.

## 3. Configure Function App environment settings

| Setting | Value source / meaning |
| --- | --- |
| `AZURE_SUBSCRIPTION_ID` | Subscription containing the scanned resource group |
| `AZURE_CLIENT_ID` | Function's user-assigned identity **client** ID |
| `AzureWebJobsStorage__accountName` | Host storage account name |
| `AzureWebJobsStorage__credential` | `managedidentity` |
| `AzureWebJobsStorage__clientId` | Host storage identity client ID |
| `AzureWebJobsStorage` | Empty-string workaround used in this lab; not an empty-key connection string |
| `LOGS_INGESTION_ENDPOINT` | DCR `endpoints.logsIngestion` output |
| `LOGS_DCR_IMMUTABLE_ID` | DCR immutable ID, not its ARM resource ID |

The source currently hardcodes the lab resource group, Storage endpoint, and table
name in `function_app.py`. Adapt these for another environment. The stream name is
`Custom-NsgFindings`; it must match the DCR declaration exactly.

Configure HTTPS and platform authentication to require Entra tokens, return 401
for unauthenticated requests, and accept the target API audience. Include both the
Logic App and web VM client IDs in `allowed_applications` and their principal IDs
in `allowed_identities`. Keep these values in the owning Terraform configuration.
Allowing a caller here applies to the Function App, not only a single route.

## 4. Run and publish Python

From the repository root, create/activate a local environment and install the
function-specific requirements:

```bash
python3.14 -m venv .venv
source .venv/bin/activate
python -m pip install -r Python/functions/requirements.txt
az login
```

Set `AZURE_SUBSCRIPTION_ID` in the shell or a local ignored `.env`. Leave
`AZURE_CLIENT_ID` unset locally to select CLI credentials. The local user needs
the appropriate data-plane and DCR permissions too; cloud identity grants do not
give the local account access.

If using a root `.env`, load it into the local shell or place it on the dotenv
search path. It must never be published. `LOGS_INGESTION_ENDPOINT` and
`LOGS_DCR_IMMUTABLE_ID` must be set for nonempty scan ingestion.

```bash
cd Python/functions
func start
```

In another terminal:

```bash
curl -i -X POST http://localhost:7071/api/nsg_checker
curl -i http://localhost:7071/api/findings
```

The checker writes/deletes scoped findings and can upload logs even when run
locally. Use the isolated lab and do not run it concurrently with a live checker.
Local Core Tools testing does not validate deployed Entra authorization.

After reviewing code and applying required app settings, publish from the
function directory with the local environment active:

```bash
func azure functionapp publish YOUR_FUNCTION_APP_NAME
```

This uploads the Function App project and builds its dependencies remotely. It
does not apply Terraform or perform an NSG scan. Keep `.funcignore` excluding
`.env`, virtual environments and `local.settings.json`. Do not paste function
keys into URLs/screenshots. This deployed design uses Entra bearer tokens instead.

## 5. Connect detection, orchestration, and ingestion

1. Configure the NSG-change scheduled rule for successful NSG writes/rule writes/deletes in scope, every five minutes with a one-hour lookback. Incident creation is disabled for this first rule.
2. Configure alert-created automation to match `AlertAnalyticRuleIds` against the first rule's full resource ID. That ID is resolved by Terraform at deployment, then compared by Sentinel at runtime.
3. Route the automation to the Logic App. Sentinel's service identity needs permission to run the playbook.
4. In the workflow, add a 30-minute Wait action followed by a built-in HTTP action: POST to `/api/nsg_checker`, managed-identity authentication, and the Function API audience. Run it after Delay succeeds.
5. Match the DCR input schema to the custom table: `TimeGenerated` datetime and the six string fields described in the architecture notes. Use `source` as the pass-through transform and `Custom-NsgFindings_CL` as the output stream.
6. Grant the Function identity Monitoring Metrics Publisher **on the DCR**. Python performs the upload; the DCR does not poll Storage.
7. Create a separate finding analytics rule: filter risky InternetSSH events, make one alert per query result, map `NsgId` as an AzureResource entity, and enable incidents.
8. Group using a custom `FindingKey` of normalized NSG ID + rule name + check type, with a three-hour lookback and closed-incident reopening disabled.

The lab queries use a one-hour event lookback and `ingestion_time() > ago(5m)`.
These filters are not an exactly-once or lossless scheduling mechanism. Check actual
rule execution and ingestion times when diagnosing missed events. The current
provider uses the `incident` block; older examples may use `incident_configuration`.

## 6. Add the private dashboard

Use the [dashboard guide](../dashboard/README.md). It includes a reference Flask
backend, Gunicorn/systemd configuration, Nginx proxy, static files, and SSH tunnel.
Browser JavaScript requests `/api/findings` on its own origin. It never requests
an Azure token or calls Table Storage directly.

## 7. Verify the entire path

Follow the [test matrix](validation.md). Check the Logic App output, Table entity,
custom log row, alert, incident, and page separately. A page fetch timestamp is
not the scan timestamp. No rows is not proof that a scan completed.

## Costs and cleanup

This project uses billable resources. Actual spend depends on executions, delayed
workflow runs, log ingestion/retention, Storage operations, and the existing VM.
No measured cost benchmark is claimed. Reusing a VM does not make it free.

When finished testing, restrict/remove the isolated demo rule through the owning
IaC and allow a successful scan to clear the saved finding. Close test incidents
manually if appropriate; there is no automatic closure. Review queued runs.
Do not destroy the shared resource group or the base lab to clean up this project.
Any resource teardown requires checking ownership and reviewing a separate plan.
