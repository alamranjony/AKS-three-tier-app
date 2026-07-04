resource "azurerm_kubernetes_cluster" "this" {
  name                = var.cluster_name
  location            = var.location
  resource_group_name = var.resource_group_name
  dns_prefix          = "${var.project_name}-${var.environment}"
  # kubernetes_version  = var.kubernetes_version
  tags                = var.tags

  # System-assigned managed identity - avoids storing a service principal
  # secret for the cluster itself.
  identity {
    type = "SystemAssigned"
  }

  default_node_pool {
    name                = "system"
    vm_size             = var.node_size
    vnet_subnet_id      = var.aks_subnet_id
    node_count          = var.node_count
    auto_scaling_enabled = true
    min_count           = var.node_min_count
    max_count           = var.node_max_count
    max_pods            = 30
    os_disk_size_gb     = 64
    type                = "VirtualMachineScaleSets"
    upgrade_settings {
      max_surge = "33%"
    }
  }

  network_profile {
    network_plugin    = "azure"
    network_policy    = "azure" # enables Kubernetes NetworkPolicy enforcement
    load_balancer_sku = "standard"
    service_cidr      = "10.20.0.0/16"
    dns_service_ip    = "10.20.0.10"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  oms_agent {
    log_analytics_workspace_id = var.log_analytics_workspace_id
  }

  azure_policy_enabled = true

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count, # let the autoscaler manage this
    ]
  }
}

# Grant AKS's kubelet identity permission to pull images from ACR without
# needing `docker login` / imagePullSecrets.
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = var.acr_id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
}
