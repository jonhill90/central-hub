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

# The tenant ID for the OPNsense password vault.
data "azurerm_client_config" "current" {}

# Dev's read-only identity (TASK-0240, agent pick 205): a second app registration, `c1-backup-reader`,
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

# OPNsense's configuration, copied off the agent box (agent pick 222; runbook
# docs/runbooks/copy-opnsense-backup-off-box.md). The owner's card of 2026-11-14 02:23 UTC: the same
# storage account, but its own container and its own credential, so c1's backup identity can't touch
# these copies and this one can't touch c1's. The box signs in as its own app registration with a
# certificate made on the box (the same script as the nodes, pick 189): no secret here or in state.
# Its role is on this container only; c1's two apps hold roles on the c1 container only.
resource "azurerm_storage_container" "opnsense" {
  name                  = var.opnsense_container_name
  storage_account_id    = azurerm_storage_account.backup.id
  container_access_type = "private"
}

resource "azuread_application" "opnsense" {
  display_name     = var.opnsense_app_display_name
  sign_in_audience = "AzureADMyOrg"
  owners           = [data.azuread_client_config.current.object_id]
}

resource "azuread_service_principal" "opnsense" {
  client_id = azuread_application.opnsense.client_id
  owners    = [data.azuread_client_config.current.object_id]
}

resource "azurerm_role_assignment" "opnsense" {
  scope                = azurerm_storage_container.opnsense.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azuread_service_principal.opnsense.object_id
  principal_type       = "ServicePrincipal"
}

# The OPNsense copies' restic password, kept off the box (pick 222). The box makes the password itself
# and writes it straight into this vault, signed in as the OPNsense app, so it never passes a
# transcript, the repository or tofu state: tofu makes the vault and the role, never the secret.
# The app may only set the secret and read its metadata (a custom role), so a box that is taken over
# can't read the password back or delete an earlier version. c1's apps hold nothing here. The owner
# reads it only for a recovery, by giving their own account Key Vault Secrets User then.
resource "azurerm_key_vault" "opnsense" {
  name                          = var.opnsense_vault_name
  location                      = azurerm_resource_group.backup.location
  resource_group_name           = azurerm_resource_group.backup.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = var.opnsense_vault_retention_days
  public_network_access_enabled = true

  network_acls {
    default_action = "Deny"
    bypass         = "None"
    ip_rules       = var.allowed_ip_addresses
  }

  tags = var.tags
}

resource "azurerm_role_definition" "opnsense_escrow" {
  name        = var.opnsense_escrow_role_name
  scope       = azurerm_resource_group.backup.id
  description = "Set a secret and read secrets' metadata, never their values (central-hub pick 222)."

  permissions {
    actions = []
    data_actions = [
      "Microsoft.KeyVault/vaults/secrets/setSecret/action",
      "Microsoft.KeyVault/vaults/secrets/readMetadata/action",
    ]
  }

  # Azure takes a custom role's assignable scopes down to a resource group only; the assignment below
  # is on the vault itself.
  assignable_scopes = [azurerm_resource_group.backup.id]
}

resource "azurerm_role_assignment" "opnsense_escrow" {
  scope              = azurerm_key_vault.opnsense.id
  role_definition_id = azurerm_role_definition.opnsense_escrow.role_definition_resource_id
  principal_id       = azuread_service_principal.opnsense.object_id
  principal_type     = "ServicePrincipal"
}

# Narrowing of the agents' own Azure rights (agent pick 247). Off by default: with
# narrow_agent_access = false (the default) nothing here is planned. The apply that turns it on, and
# the removal of agent-azure's Owner role afterwards, run only on the owner's tap (runbook
# give-agents-access-to-azure.md, "Narrow agent-azure's rights").
#
# With it on, agent-azure (pinned by var.agent_object_id, so an operator's own login never becomes
# the principal) gets Role Based Access Control Administrator on the backup resource group, limited by
# a condition to the three backup roles and the three backup apps, for both adding and removing a
# role assignment (https://learn.microsoft.com/azure/role-based-access-control/delegate-role-assignments-examples).
# Two subscription-wide deny rules stop storage account keys and Key Vault access lists being turned
# back on, which Contributor could otherwise do and then read the data
# (https://learn.microsoft.com/azure/storage/common/shared-key-authorization-prevent,
# https://learn.microsoft.com/azure/key-vault/general/assign-access-policy). Contributor cannot write
# or delete policy assignments, so once Owner is gone the rules hold against agents.

data "azurerm_subscription" "current" {}

resource "azurerm_role_assignment" "agent_role_admin" {
  count                = var.narrow_agent_access ? 1 : 0
  scope                = azurerm_resource_group.backup.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = var.agent_object_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  # Condition format 2.0: adding is checked on the request, removing on the existing assignment.
  # Roles: Storage Blob Data Contributor, Storage Blob Data Reader (built-in IDs,
  # https://learn.microsoft.com/azure/role-based-access-control/built-in-roles#storage) and the
  # escrow role's GUID. Principals: the three backup apps.
  condition = templatefile("${path.module}/agent-role-admin-condition.tftpl", {
    roles = join(", ", [
      "ba92f5b4-2d11-453d-a403-e96b0029c9fe",
      "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1",
      azurerm_role_definition.opnsense_escrow.role_definition_id,
    ])
    principals = join(", ", [
      azuread_service_principal.backup.object_id,
      azuread_service_principal.reader.object_id,
      azuread_service_principal.opnsense.object_id,
    ])
  })

  lifecycle {
    precondition {
      condition     = var.agent_object_id != null
      error_message = "narrow_agent_access needs agent_object_id, the object ID of agent-azure's service principal."
    }
  }
}

# Built-in "Storage accounts should prevent shared key access", effect Deny
# (https://learn.microsoft.com/azure/governance/policy/samples/built-in-policies#storage).
resource "azurerm_subscription_policy_assignment" "deny_shared_key" {
  count                = var.narrow_agent_access ? 1 : 0
  name                 = "deny-storage-shared-key"
  display_name         = "Storage accounts must not allow shared key access"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54"
  parameters           = jsonencode({ effect = { value = "Deny" } })
}

# Built-in "Azure Key Vault should use RBAC permission model", effect Deny
# (https://learn.microsoft.com/azure/key-vault/policy-reference).
resource "azurerm_subscription_policy_assignment" "deny_vault_access_policies" {
  count                = var.narrow_agent_access ? 1 : 0
  name                 = "deny-vault-access-policies"
  display_name         = "Key vaults must use RBAC, not access policies"
  subscription_id      = data.azurerm_subscription.current.id
  policy_definition_id = "/providers/Microsoft.Authorization/policyDefinitions/12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5"
  parameters           = jsonencode({ effect = { value = "Deny" } })
}
