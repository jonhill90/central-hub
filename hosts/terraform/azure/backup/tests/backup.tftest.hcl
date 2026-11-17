# Offline tests for azure/backup: the provider is mocked, so no Azure sign-in is needed and
# nothing is made in Azure (STD-0005). Values are made up, as in azure.tfvars.example. The runs
# use apply, which with a mocked provider only fills in values.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      object_id = "11111111-1111-1111-1111-111111111111"
      tenant_id = "22222222-2222-2222-2222-222222222222"
    }
  }
  mock_resource "azurerm_storage_account" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-c1-backup/providers/Microsoft.Storage/storageAccounts/examplec1backup"
    }
  }
  mock_resource "azurerm_storage_container" {
    defaults = {
      id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-c1-backup/providers/Microsoft.Storage/storageAccounts/examplec1backup/blobServices/default/containers/c1-backup"
    }
  }
}

mock_provider "azuread" {
  mock_data "azuread_client_config" {
    defaults = {
      object_id = "11111111-1111-1111-1111-111111111111"
      tenant_id = "22222222-2222-2222-2222-222222222222"
    }
  }
  mock_resource "azuread_application" {
    defaults = {
      client_id = "33333333-3333-3333-3333-333333333333"
      object_id = "44444444-4444-4444-4444-444444444444"
    }
  }
  mock_resource "azuread_service_principal" {
    defaults = {
      object_id = "55555555-5555-5555-5555-555555555555"
    }
  }
}

variables {
  location             = "eastus2"
  storage_account_name = "examplec1backup"
  allowed_ip_addresses = ["203.0.113.10"]
  opnsense_vault_name  = "example-opnsense-kv"
}

# No raw keys (owner, 2026-11-08 23:42 UTC): the account refuses shared key and anonymous reads.
run "no_keys_no_anonymous_access" {
  assert {
    condition     = azurerm_storage_account.backup.shared_access_key_enabled == false
    error_message = "Shared key access must be off, so no account key or key-signed SAS works."
  }

  assert {
    condition     = azurerm_storage_account.backup.allow_nested_items_to_be_public == false
    error_message = "No blob or container may be made public."
  }

  assert {
    condition     = azurerm_storage_container.backup.container_access_type == "private"
    error_message = "The container must be private."
  }

  assert {
    condition     = azurerm_storage_account.backup.local_user_enabled == false && azurerm_storage_account.backup.sftp_enabled == false
    error_message = "Local users and SFTP each bring their own passwords or keys; both must be off."
  }

  assert {
    condition     = azurerm_storage_account.backup.https_traffic_only_enabled && azurerm_storage_account.backup.min_tls_version == "TLS1_2"
    error_message = "HTTPS only, TLS 1.2 at least."
  }
}

# The data endpoint answers only the listed addresses, and no Azure service is let through.
run "only_listed_addresses" {
  assert {
    condition     = azurerm_storage_account.backup.network_rules[0].default_action == "Deny"
    error_message = "The network default must be Deny."
  }

  assert {
    condition     = length(azurerm_storage_account.backup.network_rules[0].ip_rules) == 1 && contains(azurerm_storage_account.backup.network_rules[0].ip_rules, "203.0.113.10")
    error_message = "ip_rules must be exactly allowed_ip_addresses."
  }

  assert {
    condition     = length(azurerm_storage_account.backup.network_rules[0].bypass) == 1 && contains(azurerm_storage_account.backup.network_rules[0].bypass, "None")
    error_message = "No bypass for Azure services, logging or metrics."
  }
}

run "deleted_blobs_come_back" {
  assert {
    condition     = azurerm_storage_account.backup.blob_properties[0].delete_retention_policy[0].days == 7
    error_message = "Deleted blobs must be kept 7 days by default."
  }

  assert {
    condition     = azurerm_storage_account.backup.blob_properties[0].container_delete_retention_policy[0].days == 7
    error_message = "A deleted container must be kept 7 days by default."
  }
}

run "outputs_for_restic" {
  assert {
    condition     = output.restic_repository == "azure:c1-backup:/c1"
    error_message = "restic_repository must be azure:<container>:/c1."
  }

  assert {
    condition     = endswith(output.storage_account_id, "/storageAccounts/examplec1backup")
    error_message = "storage_account_id must be the account's resource ID."
  }
}

run "refuses_a_slash_32" {
  command = plan

  variables {
    allowed_ip_addresses = ["203.0.113.10/32"]
  }

  expect_failures = [var.allowed_ip_addresses]
}

run "refuses_no_address" {
  command = plan

  variables {
    allowed_ip_addresses = []
  }

  expect_failures = [var.allowed_ip_addresses]
}

run "refuses_a_bad_account_name" {
  command = plan

  variables {
    storage_account_name = "Bad-Name"
  }

  expect_failures = [var.storage_account_name]
}

# The nodes sign in as the backup app, whose service principal gets blob data access on the backup
# container only, and nothing else in this folder holds a data role.
run "backup_app_role_on_the_container_only" {
  assert {
    condition     = azurerm_role_assignment.backup.role_definition_name == "Storage Blob Data Contributor"
    error_message = "The backup app needs Storage Blob Data Contributor."
  }

  assert {
    condition     = azurerm_role_assignment.backup.scope == azurerm_storage_container.backup.id
    error_message = "The role must be scoped to the backup container only."
  }

  assert {
    condition     = azurerm_role_assignment.backup.principal_id == "55555555-5555-5555-5555-555555555555" && azurerm_role_assignment.backup.principal_type == "ServicePrincipal"
    error_message = "The role must go to the backup app's service principal."
  }
}

# agent-azure, which runs tofu, owns the app, so it can upload a node's first certificate with
# Application.ReadWrite.OwnedBy; the app itself is single-tenant.
run "backup_app_owned_by_the_runner" {
  assert {
    condition     = contains(azuread_application.backup.owners, "11111111-1111-1111-1111-111111111111") && length(azuread_application.backup.owners) == 1
    error_message = "The app's one owner must be the identity running tofu."
  }

  assert {
    condition     = azuread_application.backup.sign_in_audience == "AzureADMyOrg"
    error_message = "The app must be single-tenant."
  }

  assert {
    condition     = output.client_id == "33333333-3333-3333-3333-333333333333" && output.app_object_id == "44444444-4444-4444-4444-444444444444" && output.tenant_id == "22222222-2222-2222-2222-222222222222"
    error_message = "The outputs must give the app's client ID, object ID and the tenant for the inventory."
  }
}

# Dev's restore identity (TASK-0240) reads the backup container and nothing else: a data role that
# can't write or delete, scoped to the container, on its own app that the runner owns.
run "reader_app_reads_the_container_only" {
  assert {
    condition     = azurerm_role_assignment.reader.role_definition_name == "Storage Blob Data Reader"
    error_message = "Dev's reader app must hold Storage Blob Data Reader, never a role that writes."
  }

  assert {
    condition     = azurerm_role_assignment.reader.scope == azurerm_storage_container.backup.id
    error_message = "The reader's role must be scoped to the backup container only."
  }

  assert {
    condition     = azurerm_role_assignment.reader.principal_id == azuread_service_principal.reader.object_id && azurerm_role_assignment.reader.principal_type == "ServicePrincipal"
    error_message = "The reader's role must go to the reader app's service principal."
  }

  assert {
    condition     = contains(azuread_application.reader.owners, "11111111-1111-1111-1111-111111111111") && length(azuread_application.reader.owners) == 1 && azuread_application.reader.sign_in_audience == "AzureADMyOrg"
    error_message = "The reader app must be single-tenant, with the identity running tofu as its one owner."
  }

  assert {
    condition     = azuread_application.reader.display_name != azuread_application.backup.display_name
    error_message = "The reader must be its own app, not the backup app."
  }
}

# OPNsense's copies from the agent box (agent pick 222): their own container and their own app,
# whose role is on that container only, while c1's two apps keep roles on the c1 container only.
# The mocks give every container and service principal the same ID, so these two get their own.
override_resource {
  target = azurerm_storage_container.opnsense
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-c1-backup/providers/Microsoft.Storage/storageAccounts/examplec1backup/blobServices/default/containers/opnsense-backup"
  }
}

override_resource {
  target = azuread_service_principal.opnsense
  values = {
    object_id = "66666666-6666-6666-6666-666666666666"
  }
}

run "opnsense_copies_are_separate" {
  assert {
    condition     = azurerm_storage_container.opnsense.name == "opnsense-backup" && azurerm_storage_container.opnsense.container_access_type == "private"
    error_message = "OPNsense's copies need their own private container."
  }

  assert {
    condition     = azurerm_role_assignment.opnsense.scope == azurerm_storage_container.opnsense.id && azurerm_role_assignment.opnsense.role_definition_name == "Storage Blob Data Contributor"
    error_message = "The OPNsense app's role must be Storage Blob Data Contributor on the OPNsense container only."
  }

  assert {
    condition     = azurerm_role_assignment.opnsense.principal_id == "66666666-6666-6666-6666-666666666666" && azurerm_role_assignment.opnsense.principal_type == "ServicePrincipal"
    error_message = "The OPNsense container's role must go to the OPNsense app's own service principal."
  }

  assert {
    condition     = azurerm_role_assignment.backup.scope != azurerm_storage_container.opnsense.id && azurerm_role_assignment.reader.scope != azurerm_storage_container.opnsense.id
    error_message = "c1's backup and reader apps must hold no role on the OPNsense container."
  }

  assert {
    condition     = azurerm_role_assignment.opnsense.principal_id != azurerm_role_assignment.backup.principal_id && azurerm_role_assignment.opnsense.principal_id != azurerm_role_assignment.reader.principal_id
    error_message = "The OPNsense copies need their own identity, not c1's."
  }

  assert {
    condition     = azuread_application.opnsense.display_name != azuread_application.backup.display_name && contains(azuread_application.opnsense.owners, "11111111-1111-1111-1111-111111111111") && length(azuread_application.opnsense.owners) == 1 && azuread_application.opnsense.sign_in_audience == "AzureADMyOrg"
    error_message = "The OPNsense app must be its own single-tenant app, with the identity running tofu as its one owner."
  }

  assert {
    condition     = output.opnsense_restic_repository == "azure:opnsense-backup:/opnsense"
    error_message = "opnsense_restic_repository must be azure:<OPNsense container>:/opnsense."
  }
}

run "refuses_one_container_for_both" {
  command = plan

  variables {
    opnsense_container_name = "c1-backup"
  }

  expect_failures = [var.opnsense_container_name]
}

# The OPNsense copies' restic password vault (pick 222): RBAC only, purge protection, the home address
# only, and the OPNsense app may set the secret and read metadata, never read a value or delete.
override_resource {
  target = azurerm_key_vault.opnsense
  values = {
    id        = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-c1-backup/providers/Microsoft.KeyVault/vaults/example-opnsense-kv"
    vault_uri = "https://example-opnsense-kv.vault.azure.net/"
  }
}

override_resource {
  target = azurerm_resource_group.backup
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-c1-backup"
  }
}

run "password_vault_is_set_only_for_the_box" {
  assert {
    condition     = azurerm_key_vault.opnsense.rbac_authorization_enabled && azurerm_key_vault.opnsense.purge_protection_enabled && azurerm_key_vault.opnsense.soft_delete_retention_days == 90
    error_message = "The vault needs RBAC, purge protection and 90 days of soft delete by default."
  }

  assert {
    condition     = azurerm_key_vault.opnsense.network_acls[0].default_action == "Deny" && azurerm_key_vault.opnsense.network_acls[0].bypass == "None" && azurerm_key_vault.opnsense.network_acls[0].ip_rules == toset(["203.0.113.10"])
    error_message = "The vault must answer only the listed addresses, with no bypass."
  }

  assert {
    condition     = toset(azurerm_role_definition.opnsense_escrow.permissions[0].data_actions) == toset(["Microsoft.KeyVault/vaults/secrets/setSecret/action", "Microsoft.KeyVault/vaults/secrets/readMetadata/action"]) && length(azurerm_role_definition.opnsense_escrow.permissions[0].actions) == 0
    error_message = "The escrow role may only set a secret and read secrets' metadata: no getSecret, no delete, no control-plane action."
  }

  assert {
    condition     = azurerm_role_assignment.opnsense_escrow.scope == azurerm_key_vault.opnsense.id && azurerm_role_assignment.opnsense_escrow.principal_id == "66666666-6666-6666-6666-666666666666"
    error_message = "The escrow role goes to the OPNsense app only, on the vault only."
  }

  assert {
    condition     = output.opnsense_vault_url == "https://example-opnsense-kv.vault.azure.net/"
    error_message = "opnsense_vault_url must be the vault's URI."
  }
}

run "refuses_a_bad_vault_name" {
  command = plan

  variables {
    opnsense_vault_name = "1-bad--name-"
  }

  expect_failures = [var.opnsense_vault_name]
}

# Narrowing of agent-azure's own rights (pick 247): nothing unless narrow_agent_access is on.
override_data {
  target = data.azurerm_subscription.current
  values = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000"
  }
}

override_resource {
  target = azuread_service_principal.reader
  values = {
    object_id = "77777777-7777-7777-7777-777777777777"
  }
}

override_resource {
  target = azurerm_role_definition.opnsense_escrow
  values = {
    role_definition_id          = "88888888-8888-8888-8888-888888888888"
    role_definition_resource_id = "/subscriptions/00000000-0000-0000-0000-000000000000/providers/Microsoft.Authorization/roleDefinitions/88888888-8888-8888-8888-888888888888"
  }
}

run "agent_access_unchanged_by_default" {
  assert {
    condition     = length(azurerm_role_assignment.agent_role_admin) == 0 && length(azurerm_subscription_policy_assignment.deny_shared_key) == 0 && length(azurerm_subscription_policy_assignment.deny_vault_access_policies) == 0
    error_message = "With narrow_agent_access off, nothing about agent-azure's rights may be planned."
  }
}

run "agent_access_narrowed" {
  variables {
    narrow_agent_access = true
    agent_object_id     = "99999999-9999-9999-9999-999999999999"
  }

  assert {
    condition     = azurerm_role_assignment.agent_role_admin[0].role_definition_name == "Role Based Access Control Administrator" && azurerm_role_assignment.agent_role_admin[0].scope == azurerm_resource_group.backup.id && azurerm_role_assignment.agent_role_admin[0].principal_id == "99999999-9999-9999-9999-999999999999" && azurerm_role_assignment.agent_role_admin[0].principal_type == "ServicePrincipal" && azurerm_role_assignment.agent_role_admin[0].condition_version == "2.0"
    error_message = "agent-azure gets RBAC Administrator on the backup resource group only, as the pinned principal, with a 2.0 condition."
  }

  assert {
    condition     = length(regexall("GuidEquals \\{ba92f5b4-2d11-453d-a403-e96b0029c9fe, 2a2b9908-6ea1-4ae2-8e65-a410df84e7d1, 88888888-8888-8888-8888-888888888888\\}", azurerm_role_assignment.agent_role_admin[0].condition)) == 2 && length(regexall("GuidEquals \\{55555555-5555-5555-5555-555555555555, 77777777-7777-7777-7777-777777777777, 66666666-6666-6666-6666-666666666666\\}", azurerm_role_assignment.agent_role_admin[0].condition)) == 2 && length(regexall("GuidEquals \\{", azurerm_role_assignment.agent_role_admin[0].condition)) == 4
    error_message = "The condition may name only the two blob data roles and the escrow role's GUID, and only the three backup apps, once each for adding and removing."
  }

  assert {
    condition     = length(regexall("@Request\\[Microsoft.Authorization/roleAssignments:(RoleDefinitionId|PrincipalId)\\]", azurerm_role_assignment.agent_role_admin[0].condition)) == 2 && length(regexall("@Resource\\[Microsoft.Authorization/roleAssignments:(RoleDefinitionId|PrincipalId)\\]", azurerm_role_assignment.agent_role_admin[0].condition)) == 2 && length(regexall("ActionMatches\\{'Microsoft.Authorization/roleAssignments/(write|delete)'\\}", azurerm_role_assignment.agent_role_admin[0].condition)) == 2
    error_message = "Both adding (@Request) and removing (@Resource) must be limited by role and by principal."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.deny_shared_key[0].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/8c6a50c6-9ffd-4ae7-986f-5fa6111f9a54" && jsondecode(azurerm_subscription_policy_assignment.deny_shared_key[0].parameters).effect.value == "Deny" && azurerm_subscription_policy_assignment.deny_shared_key[0].subscription_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "The shared-key rule must be the built-in with effect Deny, on the whole subscription."
  }

  assert {
    condition     = azurerm_subscription_policy_assignment.deny_vault_access_policies[0].policy_definition_id == "/providers/Microsoft.Authorization/policyDefinitions/12d4fa5e-1f9f-4c21-97a9-b99b3c6611b5" && jsondecode(azurerm_subscription_policy_assignment.deny_vault_access_policies[0].parameters).effect.value == "Deny" && azurerm_subscription_policy_assignment.deny_vault_access_policies[0].subscription_id == "/subscriptions/00000000-0000-0000-0000-000000000000"
    error_message = "The vault-model rule must be the built-in with effect Deny, on the whole subscription."
  }
}

run "agent_access_needs_the_pinned_principal" {
  command = plan

  variables {
    narrow_agent_access = true
  }

  expect_failures = [azurerm_role_assignment.agent_role_admin]
}
