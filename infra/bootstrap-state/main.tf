terraform {
  required_version = ">= 1.5.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  subscription_id                 = "7ae702da-4d24-4520-aad7-58492c430745"
  resource_provider_registrations = "none"
  storage_use_azuread             = true
}

data "azurerm_client_config" "current" {}

locals {
  tags = {
    Project     = "production-devsecops-compliance"
    Environment = "security-lab"
    ManagedBy   = "Terraform"
    Purpose     = "Terraform remote state"
  }
}

resource "azurerm_resource_group" "state" {
  name     = "production-devsecops-state-rg"
  location = "centralus"

  tags = local.tags
}

resource "azurerm_storage_account" "state" {
  name                = "proddevsecopsstate01"
  resource_group_name = azurerm_resource_group.state.name
  location            = azurerm_resource_group.state.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "ZRS"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  public_network_access_enabled     = true
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  local_user_enabled                = false
  default_to_oauth_authentication   = true
  infrastructure_encryption_enabled = true

  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
    ip_rules       = ["105.127.15.82"]
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 30
    }

    container_delete_retention_policy {
      days = 30
    }
  }

  tags = local.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_storage_container" "state" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.state.id
  container_access_type = "private"

  lifecycle {
    prevent_destroy = true
  }
}

resource "azurerm_role_assignment" "state_access" {
  scope                = azurerm_storage_container.state.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "User"
}
