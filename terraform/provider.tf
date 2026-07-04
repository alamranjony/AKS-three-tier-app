terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.1.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }

  # Remote backend for state storage + locking.
  # This storage account/container/key must be created ONE TIME manually

  backend "azurerm" {
    resource_group_name  = "devops-assessment"
    storage_account_name = "tfstate12345" # must be globally unique
    container_name       = "tfstate"
    key                  = "devops-assessment.tfstate"
  }
}

provider "azurerm" {
  subscription_id = var.subscription_id

  features {
    key_vault {
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = false
    }
  }
}
