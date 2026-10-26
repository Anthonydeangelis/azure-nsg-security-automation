# Validation and evidence

[Back to overview](../README.md)

## Observed lab outcomes

These outcomes were observed during the October 23–25, 2026 build sessions. Screenshots
are evidence of specific checkpoints, not performance benchmarks or proof of
production reliability.

| Checkpoint | Evidence / result |
| --- | --- |
| Change alert invokes delayed workflow | [October 23 run](images/logic-app-delay-completed.png) shows trigger, completed 30-minute delay, and checker HTTP 200; earlier plain-text response |
| Initial scan false negative diagnosed | Azure CLI readback showed uppercase `TCP`; helper normalization fixed the mismatch |
| Function published and host started | Core Tools remote build completed and host health check passed |
| Storage identity write | Connectivity-test entity observed, then real InternetSSH entities observed |
| DCR ingestion | [Custom table screenshot](images/log-analytics-finding.png) contains the first risky finding |
| DCR/table relationship | [Table configuration](images/custom-table-dcr.png) shows the linked DCR; this alone does not prove ingestion |
| Finding-based incident | [Incident screenshot](images/sentinel-incident.png): incident 14, Medium, one alert, NSG mapped |
| VM identity → reader API | VM test returned HTTP 200 and JSON from `/api/findings` |
| Nginx → backend → API | VM loopback request through Nginx returned HTTP 200 |
| Dashboard fetch/display | [Dashboard screenshot](images/dashboard-internet-ssh.png) shows replacement rule and detection timestamp |
| Portal/IaC drift recovery | Backend logged upstream 403 after apply; Terraform allowlists were updated; dashboard access restored |
| Stale finding removal | Old `test_ssh-01` replaced by `test-ssh-internet`; final dashboard shows only the new finding |

The incident and ingestion screenshots show the **earlier** `test_ssh-01` test.
The final dashboard shows the **later** Internet service-tag replacement. Do not
present these as one uninterrupted run with a single rule name.

The [build story](build-story.md) explains each screenshot's role and the decision
behind that stage. The [IPv6 rule editor](images/test-rule-ipv6.png) is input evidence,
not proof of save completion or effective reachability. The October 23 workflow
screenshot predates JSON output and persistence; it is not evidence for those later features.

## Local checks performed

- Python syntax parsing and SDK import checks during implementation.
- Mocked checker cases: matching finding upload, zero findings, scan failure before persistence, and ingestion failure returning 500.
- Protocol/helper regression checks: `TCP`, `Tcp`, `tcp`, wildcard, UDP, missing protocol, and restricted source.
- JavaScript syntax check and mocked finding/empty/error/invalid-response states.
- Documentation link/image-path checks and PNG asset validation.
- Reference backend syntax and mocked success, upstream 403, and exception handling. These do not verify the parameterized reference on the VM.

These were ad hoc local checks, not a committed automated test suite or a CI test
coverage claim. They did not exercise live IAM, scheduling, or concurrent scans.

## Repeatable end-to-end demo

Only use a demo NSG verified unattached to a subnet or NIC. Do not broaden real
management access or expose the private dashboard to perform a demo.

| Step | Action | Expected observation |
| --- | --- | --- |
| 1 | Apply a dedicated inbound TCP/22 Allow rule with source `Internet` in the owning Terraform configuration | Reviewed plan creates/replaces only the intended demo rule, apart from understood unrelated drift |
| 2 | Search the first analytics rule's alerts | NSG-change alert appears, then automation starts the Logic App |
| 3 | Leave the rule unchanged through the delay | Workflow waits 30 minutes, then calls the checker |
| 4 | Inspect HTTP action output | 200, positive `finding_count`, matching rule in response |
| 5 | Open Storage browser → Tables → NsgFindings | Current rule entity exists with `LastChecked` |
| 6 | Query the custom log | Finding appears after ingestion |
| 7 | Inspect Sentinel | Finding alert and incident, or grouping into a matching open incident |
| 8 | Refresh private dashboard | Saved rule appears; retrieval time differs from last-detected time |
| 9 | Restrict/remove demo rule, then complete another successful scan | That Storage finding disappears; previous logs/incidents remain |

Step 9's safe/zero-finding variant remains a useful follow-up test; the published
screenshots prove replacement cleanup, not a complete final zero-row cleanup run.

For an isolated checker test, **Submit from this action** on Call NSG Checker
bypasses Delay. That tests the API/persistence path, not end-to-end change detection
or the 30-minute wait. Avoid creating extra overlapping runs.

### Diagnostic queries

Use the appropriate workspace. Substitute the deployed rule ID if different:

```kusto
SecurityAlert
| where TimeGenerated > ago(1h)
| where AlertType contains "6bda0e6e-ffa6-47c7-b5de-36cfd9977c86"
| project TimeGenerated, AlertName, SystemAlertId
| order by TimeGenerated desc
```

```kusto
NsgFindings_CL
| where TimeGenerated > ago(1h)
| project TimeGenerated, NsgName, RuleName, CheckType, Status, Reason
| order by TimeGenerated desc
```

```kusto
SecurityAlert
| where TimeGenerated > ago(1h)
| where AlertType contains "d41b3127-066c-4e46-9676-b315badc7474"
| project TimeGenerated, AlertName, SystemAlertId
| order by TimeGenerated desc
```

Running a query manually does not trigger its scheduled analytics rule.

## Not yet demonstrated

- Safe final scan clearing all current findings, with corresponding empty dashboard evidence.
- Repeated finding alerts grouped into the same incident under controlled testing.
- Reliable behavior under overlapping scans, partial Storage writes, retries, outages, or sustained load.
- Per-route caller authorization, automatic incident closure, or automated remediation.
- A complete clean-environment Terraform deployment from this standalone repository.

## Before making the repository public

- [ ] Review the actual staged diff; do not use `git add .` without checking all untracked lab files.
- [ ] Confirm `.env`, `local.settings.json`, virtual environments, Terraform state, saved plans, and real variable files are excluded.
- [ ] Scan code **and Git history** for secrets, function keys, API keys, connection strings, and tokens. Ignoring a file does not erase an earlier commit.
- [ ] Regenerate master/host/function keys that were exposed during experimentation; do not rely on deleting screenshots alone.
- [ ] Review screenshots at full resolution for credentials, personal information, tenant/account details, and unnecessary infrastructure identifiers. Included evidence uses the already redacted screenshots provided during testing.
- [ ] Keep real SSH private keys off the repo and jump host. Use placeholder hosts/paths in setup examples.
- [ ] Reconcile the final infrastructure snippets with the owning repo before claiming this is independently deployable. Do not copy overlapping resources into a second state.
- [ ] Do not publish `.vscode` or temporary learning files by accident; review them individually.
- [ ] Keep the AI assistance disclosure and known limitations visible.
- [ ] Choose a license if others should have permission to reuse the code; none is implied by this documentation.

Suggested GitHub About text:

> Python/Azure SDK security automation: delayed NSG evaluation, Terraform-managed infrastructure, managed identity, Sentinel incidents, and a private findings dashboard.

Suggested topics: `azure`, `python`, `terraform`, `cloud-security`, `microsoft-sentinel`,
`azure-functions`, `managed-identity`, `security-automation`, `network-security`.
