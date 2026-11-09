# Offline tests for azure/backup: the provider is mocked, so no Azure sign-in is needed and
# nothing is made in Azure (STD-0005). Values are made up, as in azure.tfvars.example. The runs
# use apply, which with a mocked provider only fills in values.

mock_provider "azurerm" {
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
    error_message = "storage_account_id must be the account's resource ID, the role assignment's scope."
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
