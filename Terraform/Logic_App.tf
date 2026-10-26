# Snippet for the existing lab configuration, which already declares
# var.rg-lab, var.location and its AzureRM provider/backend.
# This deployment owns the workflow definition. Do not also manage this
# workflow through azurerm_logic_app_workflow or separate action/trigger resources.

variable "nsg_workflow_name" {
  description = "Name of the existing portal-created Logic App to manage."
  type        = string
  default     = "NSG-change"
}

variable "nsg_sentinel_connection_name" {
  description = "Existing managed-identity Sentinel API connection in the same resource group and region as the workflow."
  type        = string
  default     = "azuresentinel-1"
}

resource "azurerm_resource_group_template_deployment" "nsg_change_workflow" {
  name                = "nsg-change-workflow"
  resource_group_name = var.rg-lab
  deployment_mode     = "Incremental"

  template_content = file("${path.module}/templates/nsg-change.logic-app.json")

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
}
