# Variables with no default are private values or place values. Private ones are filled at apply
# time and never written in this repository; set them in the git-ignored azure.tfvars.

variable "location" {
  description = "Azure region for the resource group and the storage account. A place value. No default."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group that holds only c1's backup storage, so its role assignment and its deletion stay separate from everything else."
  type        = string
  default     = "rg-c1-backup"
}

variable "storage_account_name" {
  description = "Storage account name: 3 to 24 lowercase letters and digits, unique in all of Azure, and part of a public DNS name (<name>.blob.core.windows.net). Private. No default."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9]{3,24}$", var.storage_account_name))
    error_message = "storage_account_name must be 3 to 24 lowercase letters and digits."
  }
}

variable "container_name" {
  description = "Blob container that holds the restic repository (RESTIC_REPOSITORY azure:<container>:/c1)."
  type        = string
  default     = "c1-backup"
}

variable "allowed_ip_addresses" {
  description = "Public IPv4 addresses or ranges allowed to reach the account's data (blob) endpoint: the home's public address, which c1 and the Mac both leave through. A bare address, not /32 or /31 (Azure refuses those). Private. No default."
  type        = list(string)

  validation {
    condition     = length(var.allowed_ip_addresses) > 0 && alltrue([for a in var.allowed_ip_addresses : can(cidrhost(strcontains(a, "/") ? a : "${a}/32", 0)) && !endswith(a, "/32") && !endswith(a, "/31")])
    error_message = "allowed_ip_addresses needs at least one IPv4 address or CIDR, and no /32 or /31 (give a bare address instead)."
  }
}

variable "soft_delete_days" {
  description = "Days a deleted blob or container can still be brought back. Covers a prune or a delete by mistake, including one by an agent."
  type        = number
  default     = 7

  validation {
    condition     = var.soft_delete_days >= 1 && var.soft_delete_days <= 365 && floor(var.soft_delete_days) == var.soft_delete_days
    error_message = "soft_delete_days must be a whole number from 1 to 365."
  }
}

variable "tags" {
  description = "Tags on every resource."
  type        = map(string)
  default = {
    workload   = "c1-backup"
    managed-by = "central-hub/hosts/terraform/azure/backup"
  }
}

variable "app_display_name" {
  description = "Display name of the backup's app registration in Entra ID, the identity the nodes sign in as."
  type        = string
  default     = "c1-backup"
}

variable "keep_sas_signer" {
  description = "Rollback only: true gives the identity running tofu Storage Blob Data Contributor on the account again, so the nodes' old user delegation SAS works until it expires (runbook back-up-c1-off-box.md, If it fails)."
  type        = bool
  default     = false
}

variable "reader_app_display_name" {
  description = "Display name of the read-only app registration that dev's worker signs in as to restore prod's newest volume snapshot (Storage Blob Data Reader on the container)."
  type        = string
  default     = "c1-backup-reader"
}
