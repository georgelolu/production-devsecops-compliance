terraform {
  required_version = ">= 1.5.0"

  backend "azurerm" {
    resource_group_name  = "production-devsecops-state-rg"
    storage_account_name = "proddevsecopsstate01"
    container_name       = "tfstate"
    key                  = "compliance.tfstate"
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


data "terraform_remote_state" "foundation" {
  backend = "azurerm"

  config = {
    resource_group_name  = "production-devsecops-state-rg"
    storage_account_name = "proddevsecopsstate01"
    container_name       = "tfstate"
    key                  = "foundation.tfstate"
    use_azuread_auth     = true
  }
}

variable "location" {
  description = "Azure region for the compliance lab"
  type        = string
  default     = "centralus"
}

variable "resource_group_name" {
  description = "Resource group for DevSecOps compliance resources"
  type        = string
  default     = "production-devsecops-compliance-rg"
}

variable "storage_account_name" {
  description = "Globally unique Azure Storage account name"
  type        = string
  default     = "devsecopsauditchange01"

  validation {
    condition = (
      length(var.storage_account_name) >= 3 &&
      length(var.storage_account_name) <= 24 &&
      can(regex("^[a-z0-9]+$", var.storage_account_name))
    )
    error_message = "Storage account names must contain 3-24 lowercase letters or numbers."
  }
}

variable "key_vault_name" {
  description = "Globally unique Azure Key Vault name"
  type        = string
  default     = "devsecops-kv-change01"

  validation {
    condition = (
      length(var.key_vault_name) >= 3 &&
      length(var.key_vault_name) <= 24 &&
      can(regex("^[a-zA-Z0-9-]+$", var.key_vault_name))
    )
    error_message = "Key Vault names must contain 3-24 letters, numbers, or hyphens."
  }
}

locals {
  project_tags = {
    Project     = "production-devsecops-compliance"
    Environment = "security-lab"
    ManagedBy   = "Terraform"
  }
}

data "azurerm_client_config" "current" {}

# -------------------------------------------------------------------
# RESOURCE GROUP AND CENTRAL AUDIT WORKSPACE
# -------------------------------------------------------------------



resource "azurerm_log_analytics_workspace" "audit" {
  name                = "devsecops-audit-law"
  location            = data.terraform_remote_state.foundation.outputs.location
  resource_group_name = data.terraform_remote_state.foundation.outputs.resource_group_name

  sku               = "PerGB2018"
  retention_in_days = 30

  tags = local.project_tags
}

# -------------------------------------------------------------------
# VIRTUAL NETWORK, PRIVATE ENDPOINT SUBNET AND NETWORK SECURITY
# -------------------------------------------------------------------









# -------------------------------------------------------------------
# PRIVATE DNS: AZURE STORAGE BLOB
# -------------------------------------------------------------------





# -------------------------------------------------------------------
# PRIVATE DNS: AZURE KEY VAULT
# -------------------------------------------------------------------





# -------------------------------------------------------------------
# KEY VAULT: STANDARD SKU, RBAC, NETWORK RESTRICTIONS AND PROTECTION
# -------------------------------------------------------------------

resource "azurerm_key_vault" "compliance" {
  name                = var.key_vault_name
  location            = data.terraform_remote_state.foundation.outputs.location
  resource_group_name = data.terraform_remote_state.foundation.outputs.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                   = "standard"
  rbac_authorization_enabled = true

  soft_delete_retention_days = 7
  purge_protection_enabled   = true

  # Private Endpoint is the intended access path.
  public_network_access_enabled = false

  network_acls {
    bypass                     = "None"
    default_action             = "Deny"
    ip_rules                   = []
    virtual_network_subnet_ids = []
  }

  tags = local.project_tags
}

resource "azurerm_private_endpoint" "key_vault" {
  name                = "compliance-key-vault-private-endpoint"
  location            = data.terraform_remote_state.foundation.outputs.location
  resource_group_name = data.terraform_remote_state.foundation.outputs.resource_group_name
  subnet_id           = data.terraform_remote_state.foundation.outputs.private_endpoints_subnet_id

  private_service_connection {
    name                           = "compliance-key-vault-connection"
    private_connection_resource_id = azurerm_key_vault.compliance.id
    subresource_names              = ["vault"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "key-vault-dns-zone-group"
    private_dns_zone_ids = [data.terraform_remote_state.foundation.outputs.key_vault_private_dns_zone_id]
  }

  tags = local.project_tags
}

# -------------------------------------------------------------------
# CUSTOMER-MANAGED ENCRYPTION KEY
# -------------------------------------------------------------------

resource "azurerm_key_vault_key" "storage_encryption" {
  #checkov:skip=CKV_AZURE_112: Standard Key Vault is an intentional cost-conscious lab choice. HSM-backed keys require a higher-tier design and budget.
  name         = "audit-storage-cmk"
  key_vault_id = azurerm_key_vault.compliance.id

  key_type = "RSA"
  key_size = 2048

  key_opts = [
    "decrypt",
    "encrypt",
    "unwrapKey",
    "wrapKey"
  ]

  # Long-lived lab key expiry. Establish and test a rotation procedure
  # well before this date; do not allow a storage CMK to expire unmanaged.
  expiration_date = "2036-10-27T00:00:00Z"

  depends_on = [
    azurerm_private_endpoint.key_vault
  ]
}

# -------------------------------------------------------------------
# USER-ASSIGNED IDENTITY AND KEY VAULT CRYPTO PERMISSION
# -------------------------------------------------------------------

resource "azurerm_user_assigned_identity" "storage" {
  name                = "devsecops-storage-identity"
  location            = data.terraform_remote_state.foundation.outputs.location
  resource_group_name = data.terraform_remote_state.foundation.outputs.resource_group_name

  tags = local.project_tags
}

resource "azurerm_role_assignment" "storage_key_access" {
  scope                = azurerm_key_vault.compliance.id
  role_definition_name = "Key Vault Crypto Service Encryption User"
  principal_id         = azurerm_user_assigned_identity.storage.principal_id
  principal_type       = "ServicePrincipal"
}

# -------------------------------------------------------------------
# PRIVATE STORAGE ACCOUNT WITH ZRS AND DEFENSE IN DEPTH
# -------------------------------------------------------------------

# CKV_AZURE_33 exception:
# Queue logging is configured using the dedicated
# azurerm_storage_account_queue_properties resource below.
# The Checkov rule checks the legacy inline queue_properties block
# and may not recognize the separate AzureRM 4.x resource.
#
# CKV_AZURE_206 exception:
# ZRS is an intentional cost-conscious lab decision. It provides
# zone-level redundancy, not geo-redundancy. Production workloads
# requiring regional disaster recovery should use a suitable
# geo-redundant option after evaluating regional availability and cost.
resource "azurerm_storage_account" "audit_evidence" {
  #checkov:skip=CKV_AZURE_206: ZRS is intentionally selected for zone-level resilience and cost. It does not provide cross-region disaster recovery.
  #checkov:skip=CKV_AZURE_33: Queue read/write/delete logging is configured using azurerm_storage_account_queue_properties.audit_queue_properties. Checkov checks the deprecated inline queue_properties configuration instead.
  name                = var.storage_account_name
  resource_group_name = data.terraform_remote_state.foundation.outputs.resource_group_name
  location            = data.terraform_remote_state.foundation.outputs.location

  account_tier             = "Standard"
  account_kind             = "StorageV2"
  account_replication_type = "ZRS"

  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  public_network_access_enabled     = false
  allow_nested_items_to_be_public   = false
  shared_access_key_enabled         = false
  local_user_enabled                = false
  infrastructure_encryption_enabled = true

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.storage.id]
  }

  customer_managed_key {
    key_vault_key_id          = azurerm_key_vault_key.storage_encryption.id
    user_assigned_identity_id = azurerm_user_assigned_identity.storage.id
  }

  sas_policy {
    expiration_period = "07.00:00:00"
    expiration_action = "Log"
  }

  blob_properties {
    versioning_enabled = true

    delete_retention_policy {
      days = 7
    }

    container_delete_retention_policy {
      days = 7
    }
  }

  tags = local.project_tags

  depends_on = [
    azurerm_role_assignment.storage_key_access
  ]
}

resource "azurerm_storage_account_queue_properties" "audit_queue_properties" {
  storage_account_id = azurerm_storage_account.audit_evidence.id

  logging {
    delete                = true
    read                  = true
    write                 = true
    version               = "1.0"
    retention_policy_days = 7
  }
}

# -------------------------------------------------------------------
# PRIVATE AUDIT EVIDENCE CONTAINER
# -------------------------------------------------------------------

# CKV2_AZURE_21 exception:
# Blob service read/write/delete diagnostics are configured below
# on the Blob service itself. The container-level graph check may
# not recognize that service-level diagnostic setting.
resource "azurerm_storage_container" "audit_evidence" {
  #checkov:skip=CKV2_AZURE_21: Blob read/write/delete diagnostics are configured on the Blob service by azurerm_monitor_diagnostic_setting.storage_blob_audit. The Checkov graph check does not recognize this service-level configuration.
  name                  = "audit-evidence"
  storage_account_id    = azurerm_storage_account.audit_evidence.id
  container_access_type = "private"
}

# -------------------------------------------------------------------
# STORAGE BLOB PRIVATE ENDPOINT
# -------------------------------------------------------------------

resource "azurerm_private_endpoint" "storage_blob" {
  name                = "audit-storage-blob-private-endpoint"
  location            = data.terraform_remote_state.foundation.outputs.location
  resource_group_name = data.terraform_remote_state.foundation.outputs.resource_group_name
  subnet_id           = data.terraform_remote_state.foundation.outputs.private_endpoints_subnet_id

  private_service_connection {
    name                           = "audit-storage-blob-connection"
    private_connection_resource_id = azurerm_storage_account.audit_evidence.id
    subresource_names              = ["blob"]
    is_manual_connection           = false
  }

  private_dns_zone_group {
    name                 = "storage-blob-dns-zone-group"
    private_dns_zone_ids = [data.terraform_remote_state.foundation.outputs.storage_blob_private_dns_zone_id]
  }

  tags = local.project_tags
}

# -------------------------------------------------------------------
# CENTRALIZED BLOB SERVICE AUDIT DIAGNOSTICS
# -------------------------------------------------------------------

resource "azurerm_monitor_diagnostic_setting" "storage_blob_audit" {
  name                       = "storage-blob-audit-diagnostics"
  target_resource_id         = "${azurerm_storage_account.audit_evidence.id}/blobServices/default/"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.audit.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}

resource "azurerm_monitor_diagnostic_setting" "storage_queue_audit" {
  name                       = "storage-queue-audit-diagnostics"
  target_resource_id         = "${azurerm_storage_account.audit_evidence.id}/queueServices/default/"
  log_analytics_workspace_id = azurerm_log_analytics_workspace.audit.id

  enabled_log {
    category = "StorageRead"
  }

  enabled_log {
    category = "StorageWrite"
  }

  enabled_log {
    category = "StorageDelete"
  }

  enabled_metric {
    category = "Transaction"
  }
}
