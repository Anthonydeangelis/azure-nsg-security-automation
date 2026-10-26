# Troubleshooting

[Back to portfolio overview](../README.md)

These are issues encountered while building the lab. Fixes are recorded for this
environment, not as assumptions about every provider version or Azure deployment.

## SSH rule missed because of protocol capitalization

Observed on October 25, 2026: the checker returned a successful scan with zero
findings even though the test rule allowed inbound TCP port 22 from `::/0`.
No finding was consequently written to Table Storage or Log Analytics.

The Azure rule readback showed `protocol: "TCP"`, while the helper compared it
against `"Tcp"`. Python string comparisons are case-sensitive, so that condition
was false even though the other rule properties matched.

The helper now normalizes the protocol before comparison:

```python
and (rule.protocol or "").lower() in ("tcp", "*")
```

This accepts `TCP`, `Tcp`, and `tcp`, retains wildcard support, and safely treats
a missing protocol as nonmatching. UDP and the other rule conditions are unchanged.

Local regression checks cover TCP capitalization, wildcard, UDP, missing
protocol, and restricted sources. After publishing, rerun the Logic App's
Call NSG Checker action to verify the live result without another 30-minute
delay. Confirm a nonzero finding count, the Storage row, and the ingested
`NsgFindings_CL` event. Local tests alone do not prove deployed behavior.

## Dashboard worked, then returned 403 after Terraform apply

**Symptom:** the page reported that findings could not load. Gunicorn was running,
and its logs showed `Function returned HTTP 403`. It was not a zero-finding result.

**Evidence:** the Terraform plan removed two `allowed_applications` values and the
web VM principal from `allowed_identities`. They had been configured in the portal
but were absent from desired state. The Logic App principal remained allowed.

**Fix:** represent both callers in Terraform's `auth_settings_v2.active_directory_v2`:

- `allowed_applications`: Logic App and VM managed-identity **client IDs**.
- `allowed_identities`: their **principal/object IDs**; reference the managed VM and workflow output where available.
- `allowed_audiences`: the target Function API audience, not a caller identity.

After applying, the dashboard read worked again without a new NSG scan. This was
an IaC drift lesson: a portal change may work temporarily and still be reverted
by the next apply. Do not fix a 403 by disabling authentication.

## Function deployed but the host was unhealthy

The app resource existed, but the host reported an InternalServerError. Its base
`AzureWebJobsStorage` value contained a key-based connection string with an empty
account key, alongside identity-based settings. Removing the malformed value
restored host operation. The lab represented an empty-string base setting in IaC
and retained the `__accountName`, `__credential`, and `__clientId` settings.

This was observed behavior in the deployed configuration, not proof that every
AzureRM version generates the same value. Verify live settings and the provider
version before adapting the workaround. Never print a populated connection string
or restore shared keys simply to bypass an identity configuration issue.

## Table exists but Terraform reported a shared-key 403

The table creation path reached an ACL operation that attempted key-based
authentication while shared-key access was disabled. A table could exist even
though the resource operation failed. An ARM template alternative was discussed,
and the supplied configuration retains a non-destructive state-removal block.
The current table's creation method is not confirmed. Do not create a second
competing owner or assume an existing table means every Terraform step succeeded.

## Missing local module or helper

- `azure.data.tables` requires `azure-data-tables` in the active local venv **and** Function App requirements.
- `azure.monitor.ingestion` requires `azure-monitor-ingestion` the same way.
- `from nsg import nsg_check` refers to local `nsg.py` beside `function_app.py`; it is not a package to install.
- Run `func` from `Python/functions/`, with the intended Python environment active.

## Five delayed Logic App runs at the same time

Multiple change alerts can each invoke a workflow; replacing a Terraform rule may
generate more than one change event. Delay does not combine those runs. Compare
trigger alert IDs to distinguish different alerts from repeated invocation.
The exact cause of the observed five runs was not traced to completion, and no
concurrency fix was added. This remains a known lab limitation, particularly
because multiple scans can race during snapshot cleanup.

## Page, backend, and Azure are separate checkpoints

| Observation | First check |
| --- | --- |
| Page does not open through localhost:8080 | Is the Mac's SSH tunnel still running? |
| HTML loads but JSON does not | VM `curl -i http://127.0.0.1/api/findings`, then backend journal |
| Nginx 502 | Local service active and listening on 127.0.0.1:8000? |
| Backend reports Function 403 | Entra caller allowlists, audience, and Terraform drift |
| Checker 200 with zero findings | Actual saved rule properties and deployed helper version |
| Storage row exists but no custom log | Checker status, DCR settings, schema and DCR permission; writes are not rolled back after upload failure |
| Custom log exists but no incident | Rule execution, ingestion window, alert results, enabled incident settings and grouping |

Diagnose before changing access. A dashboard fetch failure is not evidence that
the NSG is safe, that Storage is empty, or that the Logic App caller also failed.
