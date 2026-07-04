variable "resource_group_name" {
  type = string
}
variable "location" {
  type = string
}
variable "project_name" {
  type = string
}
variable "environment" {
  type = string
}
variable "cluster_name" {
  type = string
}
# variable "kubernetes_version" {
#   type = string
# }
variable "node_size" {
  type = string
}
variable "node_count" {
  type = number
}
variable "node_min_count" {
  type = number
}
variable "node_max_count" {
  type = number
}
variable "aks_subnet_id" {
  type = string
}
variable "acr_id" {
  type = string
}
variable "log_analytics_workspace_id" {
  type = string
}
variable "tags" {
  type    = map(string)
  default = {}
}
