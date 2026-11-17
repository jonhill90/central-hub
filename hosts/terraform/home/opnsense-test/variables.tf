variable "proxmox_node_name" {
  description = "The Proxmox node, same value as home/k8s."
  type        = string
}

variable "vlans_file" {
  description = "Path to the place's shared VLAN file (the same one home/network and Ansible read). No default."
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

variable "admin_user" {
  description = "Login user cloud-init makes in the FreeBSD image; the wrapper reaches the VM as this user until the bootstrap."
  type        = string
  default     = "freebsd"
}

variable "ssh_public_key" {
  description = "Public half of the SSH key the agent box's keys user configures the test VM with."
  type        = string
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
  description = "The test VM. Name (STD-0001) and address are private values set only in the box's settings."
  type = object({
    name      = string
    vm_id     = number
    address   = string
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
