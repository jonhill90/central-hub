variable "proxmox_node_name" {
  description = "The Proxmox node, same value as home/k8s."
  type        = string
}

variable "vnet" {
  description = "VNet the test copy sits on. Only dev: the copy never touches prod, mgmt or the lab firewall."
  type        = string

  validation {
    condition     = var.vnet == "dev"
    error_message = "The lab test copy goes on VNet dev only."
  }
}

variable "pool_id" {
  description = "Proxmox resource pool. The agents' user may create guests in pool dev (agent-access.sh)."
  type        = string
  default     = "dev"
}

variable "installer_iso_path" {
  description = "Path on the agent box of the Proxmox VE 9 installer ISO the wrapper prepared for the automated installation (its answer file inside: a root password hash, the box's SSH key and a static dev address)."
  type        = string
}

variable "installer_iso_sha256" {
  description = "sha256 of the prepared installer ISO, measured by the wrapper after it built it."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.installer_iso_sha256))
    error_message = "installer_iso_sha256 must be 64 lowercase hex digits."
  }
}

variable "vm" {
  description = "The test copy. Its name (STD-0001) is a private value set only in the box's settings; its address is in the installer's answer file."
  type = object({
    name      = string
    vm_id     = number
    cores     = number
    memory_mb = number
    disk_gb   = number
  })

  validation {
    condition     = var.vm.vm_id == 256
    error_message = "The lab test copy is VM 256, which the dev rebuild's tfvars never declare and whose existence its preflight refuses."
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{10,14}$", var.vm.name))
    error_message = "The test copy's name must be a STD-0001 hostname: 11 to 15 characters, a-z and 0-9, starting with a letter."
  }

  validation {
    condition     = var.vm.memory_mb >= 6144 && var.vm.disk_gb >= 32 && var.vm.cores >= 2
    error_message = "The copy holds Proxmox VE (2 GiB, its documented minimum), an OPNsense guest (3 GiB, its documented minimum) and the connector container: at least 6144 MiB, 32 GB and 2 cores (docs/specs/2026-11-lab-test-copy.md)."
  }
}
