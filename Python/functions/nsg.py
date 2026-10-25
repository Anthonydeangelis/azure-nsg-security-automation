from azure.identity import AzureCliCredential
from azure.mgmt.network import NetworkManagementClient
from azure.mgmt.network.models import SecurityRule
from dotenv import load_dotenv
import os


def includes_ssh_port(port):
    if port in ("22", "*"):
        return True

    if port and "-" in port:
        start, end = port.split("-")
        return int(start) <= 22 <= int(end)

    return False

def internet_exposed(source):
    if source in ("*", "0.0.0.0/0", "::/0", "Internet"):
        return True
    else:
        return False

def nsg_check(rule):
    ports = []
    sources = []

    if rule.destination_port_range:
        ports.append(rule.destination_port_range)

    if rule.destination_port_ranges:
        ports.extend(rule.destination_port_ranges)

    if rule.source_address_prefix:
        sources.append(rule.source_address_prefix)

    if rule.source_address_prefixes:
        sources.extend(rule.source_address_prefixes)

    return (
        rule.access == "Allow"
        and rule.direction == "Inbound"
        and rule.protocol in ("Tcp", "*")
        and any(includes_ssh_port(port) for port in ports)
        and any(internet_exposed(source) for source in sources)
    )
