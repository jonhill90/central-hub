output "storage_account_name" {
  description = "AZURE_ACCOUNT_NAME for restic, and k8s_backup_azure_account in the inventory."
  value       = azurerm_storage_account.backup.name
}

output "restic_repository" {
  description = "RESTIC_REPOSITORY for the env file."
  value       = "azure:${azurerm_storage_container.backup.name}:/c1"
}

output "storage_account_id" {
  description = "Resource ID of the storage account."
  value       = azurerm_storage_account.backup.id
}

output "client_id" {
  description = "k8s_backup_azure_client_id: the backup app's client ID, which the nodes sign in with. Not a secret."
  value       = azuread_application.backup.client_id
}

output "app_object_id" {
  description = "k8s_backup_azure_app_object_id: the backup app's object ID, which Graph addKey and removeKey take."
  value       = azuread_application.backup.object_id
}

output "tenant_id" {
  description = "k8s_backup_azure_tenant_id: the Entra ID tenant."
  value       = data.azuread_client_config.current.tenant_id
}

output "reader_client_id" {
  description = "k8s_backup_azure_client_id in dev's inventory: the read-only app's client ID. Not a secret."
  value       = azuread_application.reader.client_id
}

output "reader_app_object_id" {
  description = "k8s_backup_azure_app_object_id in dev's inventory: the read-only app's object ID."
  value       = azuread_application.reader.object_id
}

output "opnsense_restic_repository" {
  description = "repository in agent_box_opnsense_offbox: the restic repository of OPNsense's configuration copies."
  value       = "azure:${azurerm_storage_container.opnsense.name}:/opnsense"
}

output "opnsense_client_id" {
  description = "client_id in agent_box_opnsense_offbox: the OPNsense copy app's client ID, which the box signs in with. Not a secret."
  value       = azuread_application.opnsense.client_id
}

output "opnsense_app_object_id" {
  description = "app_object_id in agent_box_opnsense_offbox: the OPNsense copy app's object ID, which Graph addKey and removeKey take."
  value       = azuread_application.opnsense.object_id
}
