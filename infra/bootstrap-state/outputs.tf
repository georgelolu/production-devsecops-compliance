output "state_resource_group" {
  description = "Resource group containing the Terraform state storage account."
  value       = azurerm_resource_group.state.name
}

output "state_storage_account" {
  description = "Dedicated Terraform state storage account."
  value       = azurerm_storage_account.state.name
}

output "state_container" {
  description = "Private container for Terraform state."
  value       = azurerm_storage_container.state.name
}
