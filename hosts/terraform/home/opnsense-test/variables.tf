variable "proxmox_node_name" {
  description = "The Proxmox node, same value as home/k8s."
  type        = string
}

variable "vnet" {
  description = "VNet the test VM sits on. Only dev: the proof never touches prod or the lab firewall."
  type        = string

  validation {
    condition     = var.vnet == "dev"
    error_message = "The OPNsense test VM goes on VNet dev only."
  }
}

variable "pool_id" {
  description = "Proxmox resource pool. The agents' user may create guests in pool dev (agent-access.sh)."
  type        = string
  default     = "dev"
}

variable "seed_iso_path" {
  description = "Path on the agent box of the NoCloud seed ISO the wrapper built (hostname, root's SSH key, the static dev address)."
  type        = string
}

variable "seed_iso_sha256" {
  description = "sha256 of the seed ISO, measured by the wrapper after it built it."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.seed_iso_sha256))
    error_message = "seed_iso_sha256 must be 64 lowercase hex digits."
  }
}

variable "image_path" {
  description = "Path on the agent box of the unpacked FreeBSD 14.3 BASIC-CLOUDINIT qcow2 the wrapper checked."
  type        = string
}

variable "image_file_name" {
  description = "Name the image gets under local:import/."
  type        = string
  default     = "FreeBSD-14.3-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2"
}

variable "image_sha256" {
  description = "sha256 of the unpacked qcow2, which the wrapper measured after checking the archive's sha256 of the .xz."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{64}$", var.image_sha256))
    error_message = "image_sha256 must be 64 lowercase hex digits."
  }
}

variable "vm" {
  description = "The test VM. Its name (STD-0001) is a private value set only in the box's settings; its address is in the seed ISO."
  type = object({
    name      = string
    vm_id     = number
    cores     = number
    memory_mb = number
    disk_gb   = number
  })

  validation {
    condition     = var.vm.vm_id == 257
    error_message = "The OPNsense test VM is VM 257, which the dev rebuild's tfvars never declare and whose existence its preflight refuses."
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{10,14}$", var.vm.name))
    error_message = "The test VM's name must be a STD-0001 hostname: 11 to 15 characters, a-z and 0-9, starting with a letter."
  }

  validation {
    condition     = var.vm.memory_mb >= 3072 && var.vm.disk_gb >= 16
    error_message = "OPNsense documents 3 GB of RAM as its minimum; the disk is at least 16 GB."
  }
}
