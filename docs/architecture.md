# Architecture and design notes

[Back to portfolio overview](../README.md)

This describes the implemented lab, not every feature proposed in the original plan.

## Infrastructure inventory

| Component | Implemented role |
| --- | --- |
| Existing resource group / VNets / jump host | Shared lab environment; not provisioned from this project folder |
| `Web-Test-NSG` | Dedicated demo NSG; risky tests are intended to remain unattached to NICs/subnets |
| `NSG-config-change` | Scheduled AzureActivity query; configuration-change alerts, incident creation disabled |
| Sentinel automation | Routes alerts by originating analytics-rule ID into the playbook |
| `NSG-change` | Consumption Logic App with system identity, Sentinel trigger, 30-minute delay, authenticated POST |
| `ant-nsg-checker-01` | Linux Flex Consumption Python Function App, FC1 service plan, checker and reader routes |
| `mi-nsg-functions` | User-assigned outbound identity attached to the Function App |
| StorageV2 account | Runtime/deployment storage plus private deployment container and findings table |
| `NsgFindings` | Table Storage entities consumed by the reader |
| `dcr-nsg-findings` | Direct ingestion stream, schema, unchanged `source` transform, workspace destination |
| `NsgFindings_CL` | Custom Analytics-plan Log Analytics table |
| Finding analytics rule | Fresh risky events, one alert per result, NSG entity mapping, incident enabled |
| Existing web VM | System identity; Nginx, Flask/Gunicorn backend, systemd service, static dashboard |

The Function App, plan, runtime storage and deployment container are supporting
infrastructure; they are distinct from the findings table. DCR output values feed
Function App settings. A separate Data Collection Endpoint was not added for this
Direct DCR/public-service-endpoint setup.

## Identity and access boundaries

| Caller identity | Target | Implemented access |
| --- | --- | --- |
| GitHub OIDC service principal | Existing lab resource group | Contributor; infrastructure deployment, not RBAC role assignment |
| Sentinel service identity | Playbook resource group | Microsoft Sentinel Automation Contributor to invoke playbooks |
| Logic App system identity | Sentinel workspace | Microsoft Sentinel Reader for the configured connector path |
| Logic App system identity | Function App API | Entra allowed application/client ID and allowed identity/principal ID |
| Function user-assigned identity | Scanned resource group | Reader to inspect NSG configuration |
| Function user-assigned identity | Runtime/deployment storage | Storage Blob Data Owner as configured in the lab |
| Function user-assigned identity | Findings storage | Storage Table Data Contributor |
| Function user-assigned identity | DCR | Monitoring Metrics Publisher for logs upload |
| Web VM system identity | Function App API | Entra allowed application/client ID and allowed identity/principal ID |

The lab operator assigned roles that the GitHub deployment principal could not
grant. This documents the actual grants, not a claim that every grant is the
smallest possible custom permission set.

The VM does not need Function App Contributor or direct Table access for this
design. The Function App's outbound identity is not the incoming Logic App or VM
identity. A client ID identifies the calling application; its principal ID identifies
the service-principal object in the tenant. The audience identifies the target API.

Both routes use `AuthLevel.ANONYMOUS` only to remove the separate Functions-key
check. Deployed platform authentication requires Entra tokens, HTTPS, the configured
API audience, and allowed callers. Without that platform configuration the routes
would be exposed. These restrictions currently apply app-wide, not per route.

## API and data contracts

Checker success response:

```json
{
  "scan_status": "Succeeded",
  "finding_count": 1,
  "findings": [{
    "nsg_id": "/subscriptions/<subscription>/resourceGroups/<group>/providers/Microsoft.Network/networkSecurityGroups/<nsg>",
    "nsg_name": "Web-Test-NSG",
    "rule_name": "test-ssh-internet",
    "check_type": "InternetSSH",
    "status": "Risky",
    "reason": "Inbound SSH allowed from an unrestricted source"
  }]
}
```

Reader response:

```json
{
  "findings": [{
    "nsg_name": "Web-Test-NSG",
    "rule_name": "test-ssh-internet",
    "status": "Risky",
    "last_checked": "2026-10-25T21:48:45.614568+00:00"
  }]
}
```

The timestamps above illustrate the format; they are not a new test result.

| Table Storage property | Purpose |
| --- | --- |
| `PartitionKey` | SHA-256 of the lowercased full NSG ID |
| `RowKey` | SHA-256 of lowercased rule name plus `InternetSSH` |
| `NsgId`, `NsgName`, `RuleName` | Readable resource context |
| `CheckType`, `Status` | Finding category and risky classification |
| `LastChecked` | UTC timestamp when that matching rule was evaluated |

The DCR stream uses `TimeGenerated` (datetime) and `NsgId`, `NsgName`, `RuleName`,
`CheckType`, `Status`, `Reason` (strings). Python maps the finding fields to this
schema, using `LastChecked` for the event time. Storage's server-generated
`Timestamp` is not the same field.

The finding query creates a stable logical `FindingKey` from NSG ID, rule name,
and check type. `arg_max` collapses duplicates within a query's current results.
Incident grouping matches that custom detail within three hours. It does not
prevent later uploads, eliminate duplicate alerts, or confirm a rule is still risky.

## Failure behavior and chosen scope

The read/evaluation phase completes before reconciliation starts. An exception
during scanning skips cleanup. Storage failures can leave partial reconciliation;
an upload failure occurs after Storage changes and returns HTTP 500 without rollback.
Successful scans with no findings update Storage but send no log event.

The simpler snapshot design was chosen instead of implementing a historical
finding/resolution state machine. No safe/deleted/failed scan ledger, automatic
incident closure, scan lock, or remediation loop has been added. These are honest
boundaries of this iteration, not features implied by the architecture diagram.

## Dashboard network path

```text
Mac browser localhost:8080
  → SSH forwarding through management jump host
  → web VM Nginx port 80
  → /api/findings proxy to Gunicorn 127.0.0.1:8000
  → VM identity token for Function API
  → HTTPS GET /api/findings
  → TableClient reads saved entities
  ← JSON response returns along the same path
```

The browser holds no Azure token. The backend is loopback-only, and the dashboard
was demonstrated over the SSH tunnel. Serving HTTP on the VM is not a substitute
for HTTPS/user authentication if this is ever made public.
