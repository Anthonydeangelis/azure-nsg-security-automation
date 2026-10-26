# Azure NSG Risk Evaluation Project Plan

> Archived initial planning document. The project evolved during implementation.
> Use [README.md](README.md) and [docs/architecture.md](docs/architecture.md) for
> the current design and verified status. In particular, deployment remained in
> the existing lab's owning Terraform state; the checker scans the resource group,
> and snapshot cleanup replaced the proposed history/resolution state machine.
> Remediation, per-route authorization, and concurrency controls were not implemented.

## Purpose

Extend the existing Azure infrastructure/security lab with a small, understandable system that evaluates Network Security Group (NSG) changes, records findings, creates Microsoft Sentinel incidents only for risky findings, presents results in a dashboard, and later supports narrowly controlled remediation.

This project is intentionally incremental. Infrastructure comes first, followed by small Python lessons and integrations. The full application will not be built at once.

## Relationship to the existing lab

The existing lab is managed separately:

- Repository: <https://github.com/Anthonydeangelis/Azure-Infra-Security-Lab>
- Remote working path previously reported: `/home/labadmin/Azure-Infra-Security-Lab`
- Resource group previously reported: `rg-azure-infra-security-lab`

That remote path is not available in this local project, and the current Azure deployment state must be verified before any deployment.

The existing lab reportedly includes Terraform remote state, GitHub Actions OIDC reviewed-plan deployment, five Ubuntu VMs, virtual networks and NSGs, a private Nginx web VM, Ansible, a management jump host, Log Analytics, Sentinel NSG-change and SSH detections, DNS reputation automation, and an incident email Logic App.

## State and ownership boundary

This repository will own only the new resources introduced for NSG risk evaluation. Existing lab resources remain owned by the existing lab's Terraform state.

Rules for this boundary:

- Reference existing resources through Terraform data sources or explicit input IDs.
- Do not copy existing resource definitions into this project.
- Do not import existing resources into this project's state without a separate, reviewed decision.
- Use a separate remote Terraform state for this project before the first deployment.
- Do not commit state files, saved plans, credentials, secrets, or real `.tfvars` files.
- Provide sanitized example variable files and document all cross-project dependencies.
- Keep temporary unsafe test rules outside Terraform so Terraform does not normalize them away during a test.
- Create temporary unsafe rules only in a dedicated, initially unattached demo NSG.

## Target architecture

1. The existing scheduled Sentinel NSG-change analytics rule continues creating alerts, but its incident creation is disabled. This portal setting must be verified rather than assumed, then represented in the existing lab's Terraform so it cannot drift back.
2. A Sentinel alert-created automation rule invokes a Logic App.
3. The Logic App waits 30 minutes, then calls the checker function with the affected resource identifiers. This grace period is additional to detection and ingestion delay.
4. The checker uses the Azure SDK for Python to read the NSG's current configuration.
5. Deleted rules and safe rules are recorded without creating risk incidents. Read, authentication, parsing, and other errors are recorded as errors and are never classified as safe.
6. Findings are persisted and ingested into a custom Log Analytics table.
7. A separate finding-based Sentinel analytics rule creates alert-backed incidents for risky findings, preserving Defender/Sentinel visibility.
8. The existing incident email workflow is reused for those incidents.
9. Stable identifiers and finding state deduplicate repeated source events, retries, and unchanged unresolved rules. Changes caused by future remediation must not create response loops.
10. One Function App hosts two separate functions:
    - A checker endpoint invoked only by the Logic App.
    - A read-only findings API used by the dashboard; it exposes no checker or remediation controls.
11. Storage persists findings and deduplication state.
12. The existing private Nginx VM may later serve the dashboard through Ansible. A public demo, custom domain, or HTTPS exposure requires a separate ingress and hosting design.
13. Later remediation is narrow and controlled, verifies the result by rereading Azure, and preserves before/after audit evidence. Terraform desired state must be coordinated so it cannot restore an unsafe rule.

## Initial risk rule

The first evaluator detects an inbound `Allow` rule that exposes SSH to the internet. It must handle Azure NSG singular and plural fields, including wildcard values, protocol values, individual ports, and port ranges.

An NSG rule match is a configuration-risk finding, not proof that a host is reachable end to end. Routing, subnet and NIC associations, host firewalls, application state, and other controls may still prevent access.

The previously reported example rule is `nsg-test/TEST_ALERT`: inbound `Deny`, source `*`, destination port `8080`, protocol `*`, priority `4095`. It is useful as an observed change example but should not trigger the initial internet-SSH risk category.

## Infrastructure work, in order

### 1. Inventory and dependency contract

Before writing deployable Terraform, inspect the existing lab repository and current Azure configuration. Record the exact IDs and settings needed by this project:

- Subscription and tenant context.
- Resource group and Azure region.
- Log Analytics workspace and Sentinel onboarding.
- Existing NSG-change analytics rule and its alert/incident settings.
- Existing automation rules, Logic Apps, connections, and incident email workflow.
- Existing private Nginx VM and its networking, for later dashboard work only.
- Existing naming, tags, provider constraints, OIDC workflow, and remote-state conventions.

This becomes a small dependency table in the README and a sanitized `terraform.tfvars.example`.

### 2. Terraform foundation

Define this project's provider/version constraints, inputs, naming conventions, tags, remote-state backend convention, and data sources for dependencies. Run formatting and validation without deploying.

### 3. Isolated evaluation infrastructure

Add persistent resources owned by this project:

- An unattached demo NSG.
- Function hosting resources and runtime storage.
- Findings/deduplication storage.
- A managed identity with the narrowest practical read permissions for the checker.
- Scoped roles needed to write findings and telemetry.
- Diagnostics and Application Insights/Log Analytics integration.

### 4. Event and finding integration

Add the Logic App delay and checker invocation, Sentinel alert-created automation, custom Log Analytics table and ingestion path, and finding-based Sentinel analytics rule. Integrate the existing incident email workflow. Verify deduplication and failure handling before risky-rule tests.

### 5. Controlled test path

Use the Azure SDK, not Terraform, to add and remove a temporary unsafe rule in the unattached demo NSG. Confirm that safe/deleted states create records without incidents, risky states create one incident, retries do not duplicate it, and errors remain visible as errors.

## Python learning sequence

Each step should be small enough to explain and test before proceeding:

1. Authenticate locally with `AzureCliCredential` and explain deployed managed identity authentication.
2. Retrieve one NSG rule.
3. List NSG rules.
4. Inspect returned object properties.
5. Evaluate safe and unsafe local sample objects.
6. Handle singular/plural source, protocol, and port fields and ranges.
7. Persist a finding and its stable deduplication key.
8. Deploy the checker function.
9. Connect findings to Log Analytics and Sentinel incidents.
10. Build the read-only findings API.
11. Build the dashboard.
12. Design and implement controlled remediation only after the read-only path is reliable.

Python explanations should use this mental model:

`client -> operation group -> method -> parameters -> returned object properties`

Method parameter counts vary by Azure SDK operation group; examples should be explained directly rather than turned into a large cheat sheet.

## Proposed repository layout

```text
.
|-- PROJECT_PLAN.md
|-- README.md                         # added during infrastructure inventory
|-- Python/
|   |-- checker/                      # added one lesson at a time
|   |-- findings_api/                 # added after checker persistence works
|   `-- tests/
|-- Terraform/
|   |-- versions.tf
|   |-- providers.tf
|   |-- variables.tf
|   |-- data.tf
|   |-- main.tf                       # split into focused files as it grows
|   |-- outputs.tf
|   `-- terraform.tfvars.example
|-- workflows/                        # reviewed plan/apply definitions later
`-- dashboard/                        # added only after the API is stable
```

The layout is a direction, not a request to create every file immediately.

## Security and operational requirements

- The checker endpoint must authenticate the Logic App and must not be public without an explicit access design.
- The findings API is read-only and cannot invoke checks or remediation.
- Managed identity replaces stored Azure credentials in the deployed runtime.
- RBAC is scoped narrowly; broad subscription-level roles require explicit justification.
- Logs must distinguish safe, risky, deleted, duplicate, and error outcomes.
- Sensitive resource details must be removed from any later public demo.
- Any deployment, paid SKU, public endpoint, domain, or certificate decision requires review before action.

## Current checkpoint

At project creation, the local folder contains empty `Python/` and `Terraform/` directories and `.DS_Store`. It is not yet a Git repository. No deployment or Azure mutation has been performed from this project.

## Next step

Perform the read-only inventory in **Infrastructure work, step 1**. The first concrete artifact should be a dependency contract listing exact existing Azure resource IDs/settings and deciding the new remote-state backend. Only after that review should the minimal Terraform foundation be written and validated locally.
