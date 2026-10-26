# Terraform evidence and ownership map

[Portfolio overview](../README.md) · [Build story](../docs/build-story.md)

Infrastructure for the live project was managed inside the existing
[Azure-Infra-Security-Lab](https://github.com/Anthonydeangelis/Azure-Infra-Security-Lab)
configuration and state. Start with the newly supplied
**[current project snapshot](reference/Nsg-proj.tf.example)**. It records the
completed configuration provided by the author; the other snippets preserve earlier
implementation stages. This folder is **not** a complete root module and cannot be
applied as a collection. The owning lab's [provider reference](reference/providers.tf.example)
declares Terraform 1.16.4 and AzureRM 5.0.0. A backend, complete variable contract,
and provider lockfile are not supplied here.

## Current project snapshot

`reference/Nsg-proj.tf.example` includes:

- Sentinel-triggered Logic App, 30-minute delay, and managed-identity POST action.
- Alert-created automation matching the first analytics-rule ID.
- Storage account with shared keys disabled, private deployment container, user-assigned identity, and Linux FC1 plan.
- Python 3.14 Flex Consumption Function App with identity-based storage and Entra authentication.
- Both VM and Logic App caller restrictions, including the VM principal resource reference.
- Custom Log Analytics table schema and Direct DCR, dependency ordering, and ingestion endpoint/immutable ID outputs.
- Function environment settings resolved from DCR outputs.
- Finding analytics query, entity mapping, per-result alerts, and three-hour incident grouping.

The content is preserved from the supplied file rather than redesigned for this
portfolio. The added header and `.example` extension make its reference-only status
explicit. Lab hostnames and application IDs are identifiers, not passwords; they
have not been represented as reusable values for another tenant.

The `removed` block is evidence of the earlier Table resource state migration.
It is **not** a table creation resource or a general setup step. Do not run it
against another state without understanding that state's ownership.

## What reviewers can inspect here

| File | What it demonstrates | Status / caveat |
| --- | --- | --- |
| [reference/Nsg-proj.tf.example](reference/Nsg-proj.tf.example) | Current project-specific infrastructure supplied from the owning lab | Primary reference; depends on existing lab resources and variables |
| [reference/providers.tf.example](reference/providers.tf.example) | Terraform/AzureRM versions and Entra Storage authentication option | Read-only reference from the owning repo, not a new initialized root |
| [NSG.tf](NSG.tf) | Dedicated test NSG definition | Depends on the owning lab variables; no final test-rule resource included |
| [Sentinal_rule.tf](Sentinal_rule.tf) | AzureActivity KQL, custom alert details, entity mapping, incident-disabled change rule; inline workflow and automation | Contains an earlier trigger-only workflow and duplicates definitions in the files below |
| [Logic_App.tf](Logic_App.tf) | Parameterized ARM deployment using the AzureRM provider and an external template | Alternative to the inline workflow, not an additional deployment to apply alongside it |
| [NSG_Automation.tf](NSG_Automation.tf) | Rule-ID matching and workflow output reference; deterministic automation ID | Alternative to the inline automation; duplicate resource/variable names if combined |
| [templates/nsg-change.logic-app.json](templates/nsg-change.logic-app.json) | Sentinel webhook trigger, connector identity, parameters, and outputs | Earlier stage: `actions` is empty; does not contain the live delay/HTTP call |
| [examples/function-app-auth.tf.example](examples/function-app-auth.tf.example) | Entra audience/issuer and principal restriction | Earlier Logic-App-only example; lacks the later VM caller and two-client allowlist |
| [LOGIC_APP_NOTES.md](LOGIC_APP_NOTES.md) | Parameter flow and ownership reasoning | Historical stage notes with a current-design warning |

## Dependencies still outside the snapshot

The snapshot references or relies on the following definitions/settings, which
are not all supplied here:

- `var.rg-lab`, `var.location`, and `var.subscription_id` declarations/values.
- `azurerm_log_analytics_workspace.lab-law` and Sentinel onboarding.
- `azurerm_linux_virtual_machine.linux_vms["web"]` with its system-assigned identity.
- Existing Sentinel API connection, API app registration, and manually granted roles.
- The current ARM provisioning definition for the **Table Storage** `NsgFindings` table. The custom **Log Analytics** table is included.
- The NSG-change analytics rule, shown separately in `Sentinal_rule.tf`; do not copy that file's duplicate workflow/automation sections with this snapshot.
- Latest `test-ssh-internet` demo-rule definition and the owning GitHub Actions workflows/provider constraints.

The `NsgFindings` Table Storage table exists in the lab, but its creation method
has not been confirmed. This repository does not attribute its creation to a
manual action or to an absent ARM definition. The historical `removed` block
does not establish how the current table was provisioned.

Screenshots prove particular deployed states, not the provenance of every line.
The supplied file improves implementation evidence, but is not proof of a fresh
deployment or validation with an unknown provider version. No Terraform apply or
state change was performed while adding this reference.

## Safe use

Use the owning repo's plan/apply process. Do not apply these files all together,
run `terraform destroy` against the shared lab for project cleanup, import shared
resources into another state, or deploy a trigger-only template over the completed
workflow. An incremental ARM deployment can still overwrite a workflow's actions.

The portfolio's explanation of Terraform is grounded in the implemented lab,
supplied current snapshot, and earlier snippets. It is not a claim that this
repository independently reproduces the complete infrastructure.
