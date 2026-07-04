locals {
  project   = "logicmatrix"
  env       = terraform.workspace
  region    = "asse"
  location  = "Southeast Asia"
}

variable "subscription_id" {
  description = "Azure Subscription ID"
  type        = string
}

variable "cluster_name" {
  description = "AKS cluster name"
  type        = string
  default     = "devops-assessment-aks"
}

variable "kubernetes_version" {
  description = "Kubernetes version for AKS control plane and default node pool"
  type        = string
  default     = "1.31.13"
}

variable "node_size" {
  description = "VM SKU for the default AKS node pool"
  type        = string
  default     = "Standard_D4s_v3"
}

variable "node_count" {
  description = "Number of nodes in the default node pool (ignored if autoscaling is enabled)"
  type        = number
  default     = 2
}

variable "node_min_count" {
  description = "Minimum nodes when autoscaling is enabled"
  type        = number
  default     = 2
}

variable "node_max_count" {
  description = "Maximum nodes when autoscaling is enabled"
  type        = number
  default     = 5
}

variable "db_username" {
  type        = string
  description = "Database administrator username"
}

variable "db_password" {
  type        = string
  sensitive   = true # Prevents the password from printing in console logs
}

variable "tags" {
  description = "Common tags applied to all resources"
  type        = map(string)
  default = {
    project = "devops-assessment"
  }
}
