variable "proxmox_node_name" {
  description = "The Proxmox node, same value as home/k8s."
  type        = string
}

variable "vlans_file" {
  description = "Path to the place's shared VLAN file (the same one home/network and Ansible read). For home: ../../../ansible/inventories/home/group_vars/all/vlans.yml. No default."
  type        = string
}

variable "vnet" {
  description = "VNet the runner sits on, by name from the VLAN file. No default (STD-0004 rule 2)."
  type        = string
}

variable "template_vm_id" {
  description = "The AlmaLinux 10 VM template home/k8s owns (9000)."
  type        = number
}

variable "pool_id" {
  description = "Proxmox resource pool, named by job (STD-0001). The agents' Proxmox user may create guests only in its pools."
  type        = string
  default     = "ci"
}

variable "admin_user" {
  description = "Login user with sudo, made by cloud-init. Ansible reaches the runner as this user."
  type        = string
  default     = "admin"
}

variable "ssh_public_key" {
  description = "Public half of the SSH key the agent box's keys user configures the runner with."
  type        = string
}

variable "runner" {
  description = "The CI runner VM. Name (STD-0001) and address are private values set only in the git-ignored tfvars."
  type = object({
    name      = string
    vm_id     = number
    address   = string
    cores     = number
    memory_mb = number
    disk_gb   = number
  })

  validation {
    condition     = var.runner.vm_id >= 300 && var.runner.vm_id <= 399
    error_message = "A CI runner takes a VM ID from 300-399, the CI range in STD-0001."
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{10,14}$", var.runner.name))
    error_message = "The runner's name must be a STD-0001 hostname: 11 to 15 characters, a-z and 0-9, starting with a letter."
  }

  validation {
    condition     = var.runner.memory_mb >= 2048 && var.runner.disk_gb >= 20
    error_message = "The runner needs at least 2 GiB of RAM and 20 GB of disk (the Go build and the runner's own .NET files)."
  }
}
