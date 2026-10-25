import azure.functions as func
import logging
import os
import json
import hashlib
from datetime import datetime, timezone

from nsg import nsg_check
from azure.identity import AzureCliCredential, ManagedIdentityCredential
from azure.mgmt.network import NetworkManagementClient
from azure.data.tables import TableClient
from dotenv import load_dotenv
from findings_reader import read_findings
from azure.monitor.ingestion import LogsIngestionClient

load_dotenv()
app = func.FunctionApp()


@app.route(route="nsg_checker", methods=["POST"], auth_level=func.AuthLevel.ANONYMOUS)
def nsg_checker(req: func.HttpRequest) -> func.HttpResponse:
    logging.info("NSG checker received a request.")

    try:
        identity_client_id = os.environ.get("AZURE_CLIENT_ID")

        if identity_client_id:
            cred = ManagedIdentityCredential(client_id=identity_client_id)
        else:
            cred = AzureCliCredential()

        sub_id = os.environ["AZURE_SUBSCRIPTION_ID"]
        rg = "rg-azure-infra-security-lab"

        table_client = TableClient(
            endpoint="https://antsansgfunction01.table.core.windows.net",
            table_name="NsgFindings",
            credential=cred
        )

        client = NetworkManagementClient(cred, sub_id)
        nsgs = client.network_security_groups.list(rg)
        findings = []
        current_records = []

        for nsg in nsgs:
            nsg_rules = client.security_rules.list(rg, nsg.name)

            for rule in nsg_rules:
                if nsg_check(rule):
                    findings.append({
                        "nsg_id": nsg.id,
                        "nsg_name": nsg.name,
                        "rule_name": rule.name,
                        "check_type": "InternetSSH",
                        "status": "Risky",
                        "reason": "Inbound SSH allowed from an unrestricted source"
                    })

                    partition_key = hashlib.sha256(
                        nsg.id.lower().encode("utf-8")
                    ).hexdigest()

                    row_key = hashlib.sha256(
                        f"{rule.name.lower()}|InternetSSH".encode("utf-8")
                    ).hexdigest()

                    record = {
                        "PartitionKey": partition_key,
                        "RowKey": row_key,
                        "NsgId": nsg.id,
                        "NsgName": nsg.name,
                        "RuleName": rule.name,
                        "CheckType": "InternetSSH",
                        "Status": "Risky",
                        "LastChecked": datetime.now(timezone.utc)
                    }

                    current_records.append(record)

        # Only update storage after the entire NSG scan succeeds.
        current_keys = set()

        for record in current_records:
            table_client.upsert_entity(entity=record)
            current_keys.add((record["PartitionKey"], record["RowKey"]))

        previous_records = list(table_client.query_entities(
            query_filter="CheckType eq 'InternetSSH'"
        ))

        scope_prefix = (
            f"/subscriptions/{sub_id}/resourceGroups/{rg}/"
        ).lower()

        for previous in previous_records:
            if not previous.get("NsgId", "").lower().startswith(scope_prefix):
                continue

            key = (previous["PartitionKey"], previous["RowKey"])

            if key not in current_keys:
                table_client.delete_entity(
                    partition_key=previous["PartitionKey"],
                    row_key=previous["RowKey"]
                )

        # Send completed scan findings to the DCR's declared input stream.
        if findings:
            log_records = []

            for finding, record in zip(findings, current_records):
                log_records.append({
                    "TimeGenerated": record["LastChecked"].isoformat(),
                    "NsgId": finding["nsg_id"],
                    "NsgName": finding["nsg_name"],
                    "RuleName": finding["rule_name"],
                    "CheckType": finding["check_type"],
                    "Status": finding["status"],
                    "Reason": finding["reason"]
                })

            with LogsIngestionClient(
                endpoint=os.environ["LOGS_INGESTION_ENDPOINT"],
                credential=cred
            ) as logs_client:
                logs_client.upload(
                    rule_id=os.environ["LOGS_DCR_IMMUTABLE_ID"],
                    stream_name="Custom-NsgFindings",
                    logs=log_records
                )

    except Exception:
        logging.exception("NSG scan failed.")

        return func.HttpResponse(
            "The NSG scan could not be completed.",
            status_code=500
        )

    return func.HttpResponse(
        json.dumps({
            "scan_status": "Succeeded",
            "finding_count": len(findings),
            "findings": findings
        }),
        mimetype="application/json",
        status_code=200
    )

@app.route(
    route="findings",
    methods=["GET"],
    auth_level=func.AuthLevel.ANONYMOUS
)
def get_findings(req: func.HttpRequest) -> func.HttpResponse:
    try:
        identity_client_id = os.environ.get("AZURE_CLIENT_ID")

        if identity_client_id:
            cred = ManagedIdentityCredential(client_id=identity_client_id)
        else:
            cred = AzureCliCredential()

        table_client = TableClient(
            endpoint="https://antsansgfunction01.table.core.windows.net",
            table_name="NsgFindings",
            credential=cred
        )

        findings = read_findings(table_client)

        return func.HttpResponse(
            json.dumps({"findings": findings}),
            mimetype="application/json",
            status_code=200
        )

    except Exception:
        logging.exception("Could not read saved findings.")

        return func.HttpResponse(
            "Saved findings could not be retrieved.",
            status_code=500
        )
