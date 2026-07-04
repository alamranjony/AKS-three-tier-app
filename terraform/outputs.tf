output "cluster_name" {
  description = "AKS cluster name"
  value       = module.aks.cluster_name
}

output "cluster_endpoint" {
  description = "AKS API server endpoint"
  value       = module.aks.cluster_endpoint
  sensitive   = true
}

output "acr_login_server" {
  description = "ACR login server (used by CI/CD to push images and by k8s manifests)"
  value       = module.acr.acr_login_server
}

output "vnet_id" {
  description = "Virtual network resource ID"
  value       = module.network.vnet_id
}

output "database_fqdn" {
  description = "Private FQDN of the PostgreSQL Flexible Server"
  value       = module.database.server_fqdn
}
