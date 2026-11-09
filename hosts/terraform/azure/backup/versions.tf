terraform {
  required_version = ">= 1.10.0"

  required_providers {
    # 5.11.0 (2026-10-23) is the newest release at least two weeks old on 2026-11-09 (STD-0003
    # rule 1); 5.12.0 came out on 2026-10-29.
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "5.11.0"
    }
    # 3.10.0 (2026-09-24) is the newest release, and at least two weeks old on 2026-11-09 (STD-0003
    # rule 1). It makes the backup's own app registration in Entra ID.
    azuread = {
      source  = "hashicorp/azuread"
      version = "3.10.0"
    }
  }
}
