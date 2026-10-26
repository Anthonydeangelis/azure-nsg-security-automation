# Add to the same owning lab configuration as Logic_App.tf and Sentinal_rule.tf.
# Prerequisite: Sentinel's service identity has Microsoft Sentinel Automation
# Contributor on the playbook resource group. Reuse the existing grant if present.

variable "nsg_automation_order" {
  description = "Execution order among alert-created automation rules; choose an available order in the workspace."
  type        = number
  default     = 100

  validation {
    condition     = var.nsg_automation_order >= 1 && var.nsg_automation_order <= 1000 && floor(var.nsg_automation_order) == var.nsg_automation_order
    error_message = "The automation order must be an integer from 1 to 1000."
  }
}

resource "azurerm_sentinel_automation_rule" "nsg_change_to_playbook" {
  # Deterministic UUID: no Random provider or hardcoded subscription ID needed.
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
    # Reference the ARM deployment's output to wait for the workflow deployment.
    logic_app_id = jsondecode(
      azurerm_resource_group_template_deployment.nsg_change_workflow.output_content
    ).workflowId.value
  }
}
