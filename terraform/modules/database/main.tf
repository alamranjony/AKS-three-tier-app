resource "azurerm_private_dns_zone" "postgres" {
  name                = "${var.project_name}${var.environment}.postgres.database.azure.com"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "postgres" {
  name                  = "${var.project_name}-${var.environment}-pg-dns-link"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.postgres.name
  virtual_network_id    = var.vnet_id
}

resource "azurerm_postgresql_flexible_server" "this" {
  name                   = "${var.project_name}-${var.environment}-pg"
  resource_group_name    = var.resource_group_name
  location               = var.location
  version                = "15"
  administrator_login    = var.admin_username
  administrator_password = var.admin_password

  # VNet integration = no public endpoint at all. This is the setting
  # that guarantees "database must not be publicly exposed".
  delegated_subnet_id = var.database_subnet_id
  private_dns_zone_id = azurerm_private_dns_zone.postgres.id
  public_network_access_enabled = false

  storage_mb   = 32768
  sku_name     = "GP_Standard_D2s_v3"
  zone         = "1"
  backup_retention_days = 7

  tags = var.tags

  depends_on = [azurerm_private_dns_zone_virtual_network_link.postgres]

  lifecycle {
    ignore_changes = [administrator_password, zone]
  }
}

resource "azurerm_postgresql_flexible_server_database" "app" {
  name      = "appdb"
  server_id = azurerm_postgresql_flexible_server.this.id
  charset   = "UTF8"
  collation = "en_US.utf8"
}
