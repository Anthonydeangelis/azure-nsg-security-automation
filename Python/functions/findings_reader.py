def read_findings(table_client):
    findings = []

    records = table_client.query_entities(
        query_filter="CheckType eq 'InternetSSH'"
    )

    for record in records:
        findings.append({
            "nsg_name": record["NsgName"],
            "rule_name": record["RuleName"],
            "status": record["Status"],
            "last_checked": record["LastChecked"].isoformat()
        })

    return findings