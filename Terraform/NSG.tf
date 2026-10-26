resource "azurerm_network_security_group" "Web-Test-NSG" {
  name                = "Web-Test-NSG"
  location            = var.location
  resource_group_name = var.rg-lab
}

