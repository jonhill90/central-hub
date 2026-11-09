# Off-box storage for c1's restic backups (TASK-0194; runbook docs/runbooks/back-up-c1-off-box.md).
# Agent picks 179-182 in hosts/AGENT-PICKS.md.
#
# No key, no anonymous access: shared key access is off, so every request must carry an Entra ID
# token or a user delegation SAS (which an Entra ID identity signs). The data endpoint answers
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

# The identity that signs the SAS (agent pick 182) needs a data role: a user delegation SAS can do
# only what its signer may do, and the key that signs it can be requested only with a role on the
# account or wider. By default that is the identity running tofu, the agents' service principal.
data "azurerm_client_config" "current" {}

resource "azurerm_role_assignment" "sas_signer" {
  scope                = azurerm_storage_account.backup.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = coalesce(var.sas_signer_object_id, data.azurerm_client_config.current.object_id)
  principal_type       = "ServicePrincipal"
}
