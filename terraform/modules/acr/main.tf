resource "random_string" "acr_suffix" {
  length  = 6
  special = false
  upper   = false
}

resource "azurerm_container_registry" "this" {
  # ACR names must be globally unique, alphanumeric only.
  name                = "${var.project_name}${var.environment}acr${random_string.acr_suffix.result}"
  resource_group_name = var.resource_group_name
  location            = var.location
  sku                 = "Standard"
  admin_enabled       = false # use AKS managed identity / service principal auth instead
  tags                = var.tags
}
