# How I built the security workflow

[Portfolio overview](../README.md) · [Implementation guide](deployment.md) · [Validation record](validation.md)

## What I was trying to accomplish

I wanted to move beyond deploying Azure resources and demonstrate how I could use
them together to solve a security problem. My goal was to use the Python SDK to
evaluate NSG configuration, Terraform to manage supporting infrastructure, and
Azure identities and services to automate detection without storing credentials
in the application.

The result is a lab workflow that checks for unrestricted-source inbound SSH after
an NSG change, saves current findings, creates finding-based Sentinel incidents,
and exposes saved results through a private dashboard. The dashboard supports the
demonstration; frontend design was not my learning focus.

The screenshots below are milestones from **October 23–25, 2026**, not a single
continuous run. Each caption states what the image does and does not establish.

## 1. Start with Azure SDK reads before building automation

**What I did:** authenticated locally with `AzureCliCredential`, created a
`NetworkManagementClient`, listed NSGs, then inspected their security rules. I
expanded from one named test NSG to all NSGs in the configured resource group.

**Why:** I needed to understand the SDK's clients, operation groups, returned
objects, and property names before putting the logic behind an HTTP endpoint.
A change event alone does not describe whether the resulting configuration is risky.

**Implementation:** [checker](../Python/functions/function_app.py). The key SDK
operations are `network_security_groups.list(rg)` and
`security_rules.list(rg, nsg.name)`. Iterating those results lets the SDK retrieve
pages as needed rather than assuming the first result is the complete collection.

## 2. Define a small, explainable risk check

**What I did:** separated the evaluation into `nsg_check(rule)` and smaller port
and source helpers. A finding requires inbound Allow, TCP/wildcard, destination
port 22 or a range/wildcard covering it, and an unrestricted source value.

**Why:** separating rule evaluation from Azure I/O made the logic easier to reason
about and check locally. Singular/plural SDK properties and port ranges needed
handling; checking only `destination_port_range == "22"` was too narrow.

**Implementation:** [nsg.py](../Python/functions/nsg.py).

<details>
<summary>Evidence: initial IPv6 SSH test configuration</summary>

![Test rule editor showing IPv6 source ::/0, TCP destination port 22, and Allow](images/test-rule-ipv6.png)

This screenshot shows the earlier `test_ssh-01` rule editor with source `::/0`,
port 22, TCP, and Allow. It supports the test input, not proof of inbound direction,
save completion, NSG attachment state, or actual host reachability. CLI readback
separately confirmed the saved rule's inbound direction and other properties.
Later testing replaced this rule with `test-ssh-internet` using the Internet service tag.

</details>

**What I learned:** the saved Azure response returned protocol `TCP`, while my
helper compared it with `Tcp`. Python treated those as different strings. I
normalized the protocol with `.lower()` and checked capitalization/wildcard and
nonmatching cases. This fixed a false negative rather than changing the test to
make an incorrect evaluator appear to work. See the [root-cause notes](troubleshooting.md).

## 3. Move the checker into Azure Functions and replace local credentials

**What I did:** wrapped the scan in `POST /api/nsg_checker`, deployed Python to a
Flex Consumption Function App, and selected its user-assigned managed identity
with `AZURE_CLIENT_ID`. The deployed identity received NSG read access, findings
Storage access, and later DCR upload permission.

**Why:** on-demand execution fit the event-driven check. The Function should not
depend on my interactive CLI session or a stored service-principal password.
I created the identity before the app so its Storage permissions could be assigned
before identity-based deployment/runtime storage was used.

**Cloud understanding:** assigning Reader to the scanned resource group does not
grant Table data writes. Storage data roles, DCR upload permission, and API caller
authorization each solve a different access problem. The GitHub principal could
deploy resources but could not grant roles; I handled those grants separately.

## 4. Use Terraform to make the workflow repeatable and reviewable

**What I did:** added project resources to my existing infrastructure repo's
reviewed Terraform plan/apply workflow. I used AzureRM resources and ARM template
deployments for detailed workflow, custom table, and DCR definitions. Deployment
outputs became Function App environment settings.

**Why:** infrastructure and identity configuration should survive the next
deployment and be reviewable, not depend on remembering portal edits. I kept the
existing lab's state ownership rather than creating a competing owner for shared resources.

**Code evidence:** the [current project snapshot](../Terraform/reference/Nsg-proj.tf.example)
includes the completed Logic App, Function hosting/authentication, custom table,
DCR, and finding-based Sentinel rule supplied from my lab configuration. The
[Terraform file map](../Terraform/README.md) distinguishes it from earlier snippets
and identifies dependencies still owned by the base lab. Portal screenshots prove
deployed state, not which individual file created it. No successful GitHub Actions
screenshot is included yet, and this repo is not a clean-environment deployment package.

## 5. Separate change detection from risk escalation

**What I did:** configured the first Sentinel analytics rule to detect successful
NSG changes without creating incidents. An automation rule matches the originating
analytics-rule ID and invokes a Consumption Logic App. The app waits 30 minutes,
then sends an authenticated POST to the checker.

**Why:** every configuration edit deserves evaluation, but not every edit deserves
a risk incident. The grace period lets an administrator correct a temporary
change before the system assesses the current rules.

<details>
<summary>Evidence: completed Sentinel trigger, 30-minute wait, and checker call</summary>

![Logic App run showing successful Sentinel alert trigger, 30-minute delay, and HTTP checker action returning 200](images/logic-app-delay-completed.png)

This **October 23** run proves that the orchestration reached the checker after
the delay and received HTTP 200. It is an earlier version with a plain-text
no-findings response. It does **not** prove the later JSON response, Table writes,
or DCR ingestion. Those were added and verified in later steps.

</details>

The automation compares a stored analytics-rule ID resolved during Terraform
deployment. It does not compare a changing alert title or evaluate Terraform code
on every alert. The checker currently scans the whole configured resource group;
it does not use the alert payload to narrow the scan to one NSG.

## 6. Save findings as a current snapshot

**What I did:** used `TableClient.upsert_entity()` to persist findings with stable
PartitionKey/RowKey pairs. I then added scoped stale-row deletion after the full
read/evaluation phase. The initial connectivity-test entity proved identity-based
write access before the real finding schema was introduced.

**Why:** the dashboard needed the latest saved findings, not a growing list of
duplicate rows. A stable key lets the same issue update its row. I chose to remove
stale findings rather than build a historical resolution-state system for this iteration.

**Implementation:** [checker persistence](../Python/functions/function_app.py).
SHA-256 converts normalized identifiers into safe key strings; it is not a way
to encrypt the records. A failed scan skips reconciliation. Write-phase failures
can still leave partial results, and cleanup is not atomic or concurrency-safe.

## 7. Send detection events explicitly into Log Analytics

**What I did:** created `NsgFindings_CL`, declared the input stream/schema in a
Direct DCR, passed its ingestion endpoint and immutable ID to Python, and used
`LogsIngestionClient.upload()` with the Function identity.

**Why:** Storage diagnostics describe Storage operations; they do not forward
the contents of my Table entities. An explicit ingestion call lets Python send
the finding fields that Sentinel needs. The Storage snapshot and detection log
have different purposes and lifecycles.

<details>
<summary>Evidence: custom Analytics table linked to the DCR</summary>

![NsgFindings_CL table configuration with Analytics plan and dcr-nsg-findings link](images/custom-table-dcr.png)

This shows the deployed custom table and linked DCR. Configuration alone does not
prove any records have arrived.

</details>

![Actual InternetSSH finding ingested into NsgFindings_CL](images/log-analytics-finding.png)

**What this proves:** the earlier `test_ssh-01` finding reached the custom table
with its NSG name, rule, timestamp, category, status, and reason. This verified the
Python upload and DCR route, not just resource creation.

## 8. Create incidents from evaluated risk, not every change

**What I did:** added a second scheduled Sentinel analytics rule for newly
ingested risky InternetSSH findings. It maps the NSG as an AzureResource entity,
enables incident creation, and groups matching alerts by a logical finding key
within three hours.

**Why:** an actionable incident should represent the checker's risk assessment.
The grouping setting reduces repeated incident creation, but is not an exactly-once
delivery mechanism or proof that the rule is still risky when someone investigates.

![Sentinel incident created for the earlier SSH finding with an NSG asset](images/sentinel-incident.png)

**What this proves:** incident 14 was created for `Web-Test-NSG / test_ssh-01` with
Medium severity, one alert, and the NSG asset. It is the earlier scenario, not proof
of a new incident for the later replacement rule.

## 9. Expose saved results without putting tokens in browser code

**What I did:** added `GET /api/findings`, backed by `read_findings()`. On the existing
private web VM, a Flask/Gunicorn service requests an Entra token using the VM's
identity and calls that API. Nginx proxies the local backend and serves the static page.

**Why:** the dashboard should read saved data without initiating a scan. The
server-side proxy keeps Azure tokens out of JavaScript. I used the existing
private VM and jump-host SSH path instead of making the page publicly accessible.

**Implementation:** [reader helper](../Python/functions/findings_reader.py),
[VM proxy reference](../dashboard/backend/app.py), and [installation guide](../dashboard/README.md).
The reference proxy makes its URL/scope configurable; the live demonstration used
the same flow with those constants set in the VM file.

**What I learned:** the page later failed because Terraform removed the VM from
the Function App allowlist after I had added it only in the portal. Gunicorn's
upstream 403 log distinguished authorization failure from an empty findings table.
Adding both the VM and Logic App identities to Terraform fixed the drift.

## 10. Verify replacement cleanup and the presentation path

**What I did:** replaced the initial rule with `test-ssh-internet` through Terraform,
let the delayed checker complete, and refreshed the page. The old finding was no
longer displayed and the new service-tag finding was present.

![Final dashboard showing only the replacement Internet-source SSH rule](images/dashboard-internet-ssh.png)

**What this proves:** the result returned through Storage → reader API → VM
backend → Nginx → JavaScript, and stale-finding cleanup handled the replacement.
The retrieval time is when the page fetched data; Last detected is the scan-time
observation. Refresh does not run the checker. A final safe/zero-row cleanup test
remains a separate follow-up; this screenshot does not claim that test happened.

## Where I kept the scope small

The delivered goal is **configuration evaluation and security automation**, not
automatic remediation, live reachability testing, or a production dashboard.
I deferred scan concurrency controls and a resolution-history system rather than
claiming those capabilities. Their impact is recorded in the
[known limitations](../README.md#scope-and-known-limitations).

I used AI to create the frontend and assist with supporting code, troubleshooting,
and documentation. The learning emphasis was the Python SDK, Terraform, and
understanding the service/identity boundaries needed to connect this workflow.
