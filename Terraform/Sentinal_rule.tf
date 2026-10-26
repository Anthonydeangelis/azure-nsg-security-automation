resource "azurerm_sentinel_alert_rule_scheduled" "nsg-config" {
  name                       = "6bda0e6e-ffa6-47c7-b5de-36cfd9977c86"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab-law.id
  display_name               = "NSG-config-change"
  severity                   = "Low"
  enabled                    = true
  query_frequency            = "PT5M"
  query_period               = "PT1H"
  trigger_operator           = "GreaterThan"
  trigger_threshold          = 0
  description                = "Detects successful NSG configuration changes. Investigate authorization and potential network exposure."

  custom_details = {
    NSGName       = "NSGName"
    ResourceGroup = "ResourceGroup"
    ResourceId    = "ResourcePath"
    Actor         = "Caller"
    CallerIP      = "CallerIpAddress"
    Operation     = "OperationNameValue"
    RuleName      = "RuleName"
    EventTimeUTC  = "EventTimeUTC"
    CorrelationId = "CorrelationId"
  }

  alert_details_override {
    display_name_format = "NSG configuration changed: {{NSGName}}"
    description_format  = "Actor {{Caller}} performed {{OperationNameValue}} at {{EventTimeUTC}} UTC. Review NSG, caller IP, and correlation ID in custom details."
  }

  entity_mapping {
    entity_type = "AzureResource"

    field_mapping {
      identifier  = "ResourceId"
      column_name = "ResourcePath"
    }
  }

  event_grouping {
    aggregation_method = "AlertPerResult"
  }
  query = <<QUERY
  AzureActivity
  | where ResourceGroup =~ "rg-azure-infra-security-lab"
  | where ActivityStatusValue =~ "Success"
  | where TimeGenerated >= ago(1h)
  | where ingestion_time() > ago(5m)
  | where OperationNameValue in~ (
      "Microsoft.Network/networkSecurityGroups/write",
      "Microsoft.Network/networkSecurityGroups/securityRules/write",
      "Microsoft.Network/networkSecurityGroups/securityRules/delete"
  )
  | extend ResourcePath = coalesce(
      _ResourceId,
      ResourceId,
      tostring(Authorization_d.scope)
  )
  | extend NSGName = coalesce(
      extract(@"(?i)/networksecuritygroups/([^/]+)", 1, ResourcePath),
      "Unidentified NSG"
  )
  | extend RuleName = coalesce(
      extract(@"(?i)/securityrules/([^/]+)", 1, ResourcePath),
      "NSG-level operation"
  )
  | extend EventTimeUTC =
      format_datetime(TimeGenerated, "yyyy-MM-dd HH:mm:ss")
  | project TimeGenerated, EventTimeUTC, NSGName, RuleName,
            ResourceGroup, ResourcePath, Caller, CallerIpAddress,
            OperationNameValue, ActivityStatusValue, CorrelationId
QUERY
  incident {
    create_incident_enabled = false
    grouping {
      enabled = false
    }
  }
}

variable "nsg_workflow_name" {
  description = "Existing Logic App name."
  type        = string
  default     = "NSG-change"
}

variable "nsg_sentinel_connection_name" {
  description = "Existing Sentinel API connection in the same resource group and region."
  type        = string
  default     = "azuresentinel-1"
}

variable "nsg_automation_order" {
  description = "Order among alert-created automation rules."
  type        = number
  default     = 100
}

# Deploy the Logic App definition through ARM using the AzureRM provider.
resource "azurerm_resource_group_template_deployment" "nsg_change_workflow" {
  name                = "nsg-change-workflow"
  resource_group_name = var.rg-lab
  deployment_mode     = "Incremental"

  parameters_content = jsonencode({
    workflowName = {
      value = var.nsg_workflow_name
    }
    location = {
      value = var.location
    }
    sentinelConnectionName = {
      value = var.nsg_sentinel_connection_name
    }
  })

  template_content = jsonencode({
    "$schema"      = "https://schema.management.azure.com/schemas/2019-04-01/deploymentTemplate.json#"
    contentVersion = "1.0.0.0"

    parameters = {
      workflowName = {
        type = "string"
      }
      location = {
        type = "string"
      }
      sentinelConnectionName = {
        type = "string"
      }
    }

    resources = [
      {
        type       = "Microsoft.Logic/workflows"
        apiVersion = "2019-05-01"
        name       = "[parameters('workflowName')]"
        location   = "[parameters('location')]"

        identity = {
          type = "SystemAssigned"
        }

        properties = {
          state = "Enabled"

          definition = {
            "$schema"      = "https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#"
            contentVersion = "1.0.0.0"

            parameters = {
              "$connections" = {
                type         = "Object"
                defaultValue = {}
              }
            }

            triggers = {
              Microsoft_Sentinel_alert = {
                type = "ApiConnectionWebhook"

                inputs = {
                  host = {
                    connection = {
                      name = "@parameters('$connections')['sentinel']['connectionId']"
                    }
                  }

                  body = {
                    callback_url = "@listCallbackUrl()"
                  }

                  path = "/subscribe"
                }
              }
            }

            actions = {}
            outputs = {}
          }

          parameters = {
            "$connections" = {
              value = {
                sentinel = {
                  id = "[subscriptionResourceId('Microsoft.Web/locations/managedApis', parameters('location'), 'azuresentinel')]"

                  connectionId = "[resourceId('Microsoft.Web/connections', parameters('sentinelConnectionName'))]"

                  connectionName = "[parameters('sentinelConnectionName')]"

                  connectionProperties = {
                    authentication = {
                      type = "ManagedServiceIdentity"
                    }
                  }
                }
              }
            }
          }
        }
      }
    ]

    outputs = {
      workflowId = {
        type  = "string"
        value = "[resourceId('Microsoft.Logic/workflows', parameters('workflowName'))]"
      }

      principalId = {
        type = "string"

        value = "[reference(resourceId('Microsoft.Logic/workflows', parameters('workflowName')), '2019-05-01', 'Full').identity.principalId]"
      }
    }
  })
}

# Route alerts from the NSG analytics rule to the Logic App.
resource "azurerm_sentinel_automation_rule" "nsg_change_to_playbook" {
  name = uuidv5(
    "url",
    "${lower(azurerm_log_analytics_workspace.lab-law.id)}/automation/nsg-change-to-playbook"
  )

  log_analytics_workspace_id = azurerm_log_analytics_workspace.lab-law.id
  display_name               = "Run NSG checker on NSG change alerts"
  order                      = var.nsg_automation_order
  enabled                    = true

  triggers_on   = "Alerts"
  triggers_when = "Created"

  condition_json = jsonencode([
    {
      conditionType = "Property"

      conditionProperties = {
        propertyName = "AlertAnalyticRuleIds"
        operator     = "Contains"

        propertyValues = [
          azurerm_sentinel_alert_rule_scheduled.nsg-config.id
        ]
      }
    }
  ])

  action_playbook {
    order = 1

    logic_app_id = jsondecode(
      azurerm_resource_group_template_deployment.nsg_change_workflow.output_content
    ).workflowId.value
  }
}