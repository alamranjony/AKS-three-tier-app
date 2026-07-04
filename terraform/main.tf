resource "azurerm_resource_group" "main" {
  name     = "rg-${local.project}-${local.env}-${local.region}-001"
  location = local.location
}

module "network" {
  source = "./modules/network"

  resource_group_name  = azurerm_resource_group.main.name
  location             = local.location
  project_name         = local.project
  environment          = local.env
  tags                 = var.tags
}

module "monitoring" {
  source = "./modules/monitoring"

  resource_group_name = azurerm_resource_group.main.name
  location             = local.location
  project_name         = local.project
  environment          = local.env
  tags                 = var.tags
}

module "acr" {
  source = "./modules/acr"

  resource_group_name = azurerm_resource_group.main.name
  location             = local.location
  project_name         = local.project
  environment          = local.env
  tags                 = var.tags
}

module "aks" {
  source = "./modules/aks"

  resource_group_name        = azurerm_resource_group.main.name
  location                    = local.location
  project_name                 = local.project
  environment                  = local.env
  cluster_name                 = var.cluster_name
  # kubernetes_version           = var.kubernetes_version
  node_size                    = var.node_size
  node_count                   = var.node_count
  node_min_count                = var.node_min_count
  node_max_count                = var.node_max_count
  aks_subnet_id                = module.network.aks_subnet_id
  acr_id                        = module.acr.acr_id
  log_analytics_workspace_id   = module.monitoring.workspace_id
  tags                          = var.tags
}

module "database" {
  source = "./modules/database"

  resource_group_name = azurerm_resource_group.main.name
  location             = local.location
  project_name         = local.project
  environment          = local.env
  vnet_id              = module.network.vnet_id
  database_subnet_id   = module.network.database_subnet_id
  admin_username       = var.db_username
  admin_password       = var.db_password
  tags                 = var.tags
}
