output "storage_account_name" {
  description = "AZURE_ACCOUNT_NAME for restic, and k8s_backup_azure_account in the inventory."
  value       = azurerm_storage_account.backup.name
}

output "restic_repository" {
  description = "RESTIC_REPOSITORY for the env file."
  value       = "azure:${azurerm_storage_container.backup.name}:/c1"
}

output "storage_account_id" {
  description = "Resource ID of the storage account: the scope of the one role assignment the owner makes (Storage Blob Data Contributor for agent-azure). Azure allows the user delegation key only at account scope or wider."
  value       = azurerm_storage_account.backup.id
}
