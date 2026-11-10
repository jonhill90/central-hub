# Offline tests for azure/backup: the provider is mocked, so no Azure sign-in is needed and
# nothing is made in Azure (STD-0005). Values are made up, as in azure.tfvars.example. The runs
# use apply, which with a mocked provider only fills in values.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      object_id = "11111111-1111-1111-1111-111111111111"
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

# The way back to the SAS is off unless asked for, and then sits on the account for the runner only.
run "no_sas_signer_by_default" {
  assert {
    condition     = length(azurerm_role_assignment.sas_signer) == 0
    error_message = "The SAS signer's role must not exist unless keep_sas_signer is true."
  }
}

run "sas_signer_on_rollback" {
  variables {
    keep_sas_signer = true
  }

  assert {
    condition     = length(azurerm_role_assignment.sas_signer) == 1 && azurerm_role_assignment.sas_signer[0].scope == azurerm_storage_account.backup.id && azurerm_role_assignment.sas_signer[0].principal_id == "11111111-1111-1111-1111-111111111111"
    error_message = "With keep_sas_signer the runner gets the role on the account."
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
