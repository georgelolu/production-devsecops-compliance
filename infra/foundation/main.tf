terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    resource_group_name  = "production-devsecops-state-rg"
    storage_account_name = "proddevsecopsstate01"
    container_name       = "tfstate"
    key                  = "foundation.tfstate"
    use_azuread_auth     = true
  }

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

provider "azurerm" {
  features {}

  resource_provider_registrations = "none"
  storage_use_azuread             = true
}

variable "location" {
  description = "Azure region for the DevSecOps foundation"
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Resource group for the DevSecOps project"
  type        = string
  default     = "production-devsecops-compliance-rg"
}

variable "vnet_address_space" {
  description = "Address space reserved for the project VNet"
  type        = list(string)
  default     = ["10.50.0.0/16"]
}

variable "private_endpoints_subnet_prefix" {
  description = "Dedicated subnet for Azure private endpoints"
  type        = string
  default     = "10.50.1.0/24"
}

variable "runner_subnet_prefix" {
  description = "Dedicated subnet for the temporary Terraform runner"
  type        = string
  default     = "10.50.2.0/24"
}

locals {
  project_tags = {
    Project     = "production-devsecops-compliance"
    Environment = "security-lab"
    ManagedBy   = "Terraform"
  }
}

resource "azurerm_resource_group" "foundation" {
  name     = var.resource_group_name
  location = var.location
  tags     = local.project_tags
}

resource "azurerm_virtual_network" "foundation" {
  name                = "devsecops-compliance-vnet"
  location            = azurerm_resource_group.foundation.location
  resource_group_name = azurerm_resource_group.foundation.name
  address_space       = var.vnet_address_space
  tags                = local.project_tags
}

resource "azurerm_network_security_group" "private_endpoints" {
  name                = "devsecops-private-endpoints-nsg"
  location            = azurerm_resource_group.foundation.location
  resource_group_name = azurerm_resource_group.foundation.name
  tags                = local.project_tags
}

resource "azurerm_network_security_group" "runner" {
  name                = "devsecops-runner-nsg"
  location            = azurerm_resource_group.foundation.location
  resource_group_name = azurerm_resource_group.foundation.name
  tags                = local.project_tags
}

resource "azurerm_subnet" "private_endpoints" {
  name                 = "private-endpoints-subnet"
  resource_group_name  = azurerm_resource_group.foundation.name
  virtual_network_name = azurerm_virtual_network.foundation.name
  address_prefixes     = [var.private_endpoints_subnet_prefix]
}

resource "azurerm_subnet" "runner" {
  name                 = "terraform-runner-subnet"
  resource_group_name  = azurerm_resource_group.foundation.name
  virtual_network_name = azurerm_virtual_network.foundation.name
  address_prefixes     = [var.runner_subnet_prefix]
}

resource "azurerm_subnet_network_security_group_association" "private_endpoints" {
  subnet_id                 = azurerm_subnet.private_endpoints.id
  network_security_group_id = azurerm_network_security_group.private_endpoints.id
}

resource "azurerm_subnet_network_security_group_association" "runner" {
  subnet_id                 = azurerm_subnet.runner.id
  network_security_group_id = azurerm_network_security_group.runner.id
}

resource "azurerm_private_dns_zone" "storage_blob" {
  name                = "privatelink.blob.core.windows.net"
  resource_group_name = azurerm_resource_group.foundation.name
  tags                = local.project_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "storage_blob" {
  name                  = "storage-blob-dns-vnet-link"
  resource_group_name   = azurerm_resource_group.foundation.name
  private_dns_zone_name = azurerm_private_dns_zone.storage_blob.name
  virtual_network_id    = azurerm_virtual_network.foundation.id
  registration_enabled  = false
  tags                  = local.project_tags
}

resource "azurerm_private_dns_zone" "key_vault" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.foundation.name
  tags                = local.project_tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "key_vault" {
  name                  = "key-vault-dns-vnet-link"
  resource_group_name   = azurerm_resource_group.foundation.name
  private_dns_zone_name = azurerm_private_dns_zone.key_vault.name
  virtual_network_id    = azurerm_virtual_network.foundation.id
  registration_enabled  = false
  tags                  = local.project_tags
}

output "resource_group_name" {
  value = azurerm_resource_group.foundation.name
}

output "location" {
  value = azurerm_resource_group.foundation.location
}

output "virtual_network_id" {
  value = azurerm_virtual_network.foundation.id
}

output "private_endpoints_subnet_id" {
  value = azurerm_subnet.private_endpoints.id
}

output "runner_subnet_id" {
  value = azurerm_subnet.runner.id
}

output "storage_blob_private_dns_zone_id" {
  value = azurerm_private_dns_zone.storage_blob.id
}

output "key_vault_private_dns_zone_id" {
  value = azurerm_private_dns_zone.key_vault.id
}
