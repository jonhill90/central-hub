# The provider signs in as the agents' service principal `agent-azure`
# (docs/runbooks/give-agents-access-to-azure.md), through the Azure CLI login on the operator's
# Mac, or through ARM_TENANT_ID, ARM_CLIENT_ID and ARM_CLIENT_SECRET. The subscription comes from
# ARM_SUBSCRIPTION_ID. None of these is written in this repository.
#
# storage_use_azuread: the account allows no shared key, so any storage data call must use Entra
# ID. resource_providers_to_register: from azurerm 5.0 the provider registers nothing by itself,
# and a new subscription has Microsoft.Storage unregistered (measured 2026-11-09).
provider "azurerm" {
  features {}

  storage_use_azuread             = true
  resource_provider_registrations = "none"
  resource_providers_to_register  = ["Microsoft.Storage"]
}
