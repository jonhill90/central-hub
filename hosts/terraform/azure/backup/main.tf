# Off-box storage for c1's restic backups (TASK-0194; runbook docs/runbooks/back-up-c1-off-box.md).
# Agent picks 179-181 and 189 in hosts/AGENT-PICKS.md.
#
# No key, no anonymous access: shared key access is off, so every request must carry an Entra ID
# token (the nodes sign in as their own app registration, below). The data endpoint answers
# only the addresses in var.allowed_ip_addresses. All of this is management plane, so tofu works
# from anywhere; only reading or writing blobs needs an allowed address.

resource "azurerm_resource_group" "backup" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

resource "azurerm_storage_account" "backup" {
  name                     = var.storage_account_name
  resource_group_name      = azurerm_resource_group.backup.name
  location                 = azurerm_resource_group.backup.location
  account_kind             = "StorageV2"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  access_tier              = "Hot"

  https_traffic_only_enabled       = true
  min_tls_version                  = "TLS1_2"
  shared_access_key_enabled        = false
  default_to_oauth_authentication  = true
  allow_nested_items_to_be_public  = false
  cross_tenant_replication_enabled = false
  local_user_enabled               = false
  sftp_enabled                     = false
  allowed_copy_scope               = "AAD"
  public_network_access            = "Enabled"

  network_rules {
    default_action = "Deny"
    bypass         = ["None"]
    ip_rules       = var.allowed_ip_addresses
  }

  blob_properties {
    delete_retention_policy {
      days = var.soft_delete_days
    }
    container_delete_retention_policy {
      days = var.soft_delete_days
    }
  }

  tags = var.tags
}

resource "azurerm_storage_container" "backup" {
  name                  = var.container_name
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

# The nodes' own identity (agent pick 189): an app registration with a service principal, holding
# Storage Blob Data Contributor on the backup container only. It has no secret. Each node makes its
# own key and certificate, which never leave the node; the playbook uploads the first public
# certificate, and the node rolls it itself before it expires (Microsoft Graph addKey, which needs
# no permission for an app's own keys). So no certificate is managed here, and none is in state.
#
# The app's owner is the identity running tofu (agent-azure), which may change only apps it owns
# (Graph Application.ReadWrite.OwnedBy, docs/runbooks/give-agents-access-to-azure.md).
data "azuread_client_config" "current" {}

resource "azuread_application" "backup" {
  display_name     = var.app_display_name
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "backup" {
  client_id = azuread_application.backup.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azurerm_role_assignment" "backup" {
  scope                = azurerm_storage_container.backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.backup.object_id
  principal_type       = "ServicePrincipal"
}

# Way back to the SAS (agent pick 182, kept switched off). With keep_sas_signer = true the identity
# running tofu, agent-azure, gets Storage Blob Data Contributor on the account again, so the user
# delegation SAS it signed for the nodes works again until it expires. Only for a rollback while the
# nodes still hold that SAS; the nodes' own certificate (pick 189) needs none of this.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "sas_signer" {
  count                = var.keep_sas_signer ? 1 : 0
  scope                = azurerm_storage_account.backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
  principal_type       = "ServicePrincipal"
}

# Dev's read-only identity (TASK-0240, agent pick 202): a second app registration, `c1-backup-reader`,
# for the dev cluster's worker, which restores a read-only copy of prod's newest volume snapshot
# into dev at each rebuild (the owner's card, 2026-11-10 02:50 UTC). It holds Storage Blob Data
# Reader on the backup container only, so dev can list and read blobs and can't write or delete
# any; restic runs with --no-lock, which needs no write. Like the backup app it has no secret: the
# dev node makes its own key and certificate, and the playbook uploads the public half (the same
# code as the backup app, roles/k8s_backup with k8s_backup_reader). Owned by the identity running
# tofu, for the same upload. restic has no read-only keys, so dev's node still holds the repository
# password (access register row; rotated with everything else once the secrets store exists).
resource "azuread_application" "reader" {
  display_name     = var.reader_app_display_name
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "reader" {
  client_id = azuread_application.reader.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azurerm_role_assignment" "reader" {
  scope                = azurerm_storage_container.backup.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azuread_service_principal.reader.object_id
  principal_type       = "ServicePrincipal"
}
