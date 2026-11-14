variable "proxmox_node_name" {
  description = "The Proxmox node, same value as home/k8s."
  type        = string
}

variable "vlans_file" {
  description = "Path to the place's shared VLAN file (the same one home/network and Ansible read). For home: ../../../ansible/inventories/home/group_vars/all/vlans.yml. No default."
  type        = string
}

variable "vnet" {
  description = "VNet the store sits on, by name from the VLAN file. No default (STD-0004 rule 2)."
  type        = string
}

variable "template_vm_id" {
  description = "The agents' AlmaLinux 10 template on VNet dev (9001), a copy of the one home/k8s owns, made by home/bootstrap/agent-access.sh."
  type        = number
}

variable "pool_id" {
  description = "Proxmox resource pool the store goes in. On dev it is pool dev, where the agents' token holds its rights and a teardown doesn't remove them. null leaves it out of any pool."
  type        = string
  default     = "dev"
}

variable "admin_user" {
  description = "Login user with sudo, made by cloud-init. Ansible reaches the store as this user."
  type        = string
  default     = "admin"
}

variable "ssh_public_key" {
  description = "Public half of the SSH key the agent box's keys user configures the store with."
  type        = string
}

variable "store" {
  description = "The secrets store VM. Name (STD-0001) and address are private values set only in the git-ignored tfvars."
  type = object({
    name      = string
    vm_id     = number
    address   = string
    cores     = number
    memory_mb = number
    disk_gb   = number
  })

  validation {
    condition     = var.store.vm_id >= 500 && var.store.vm_id <= 599
    error_message = "The secrets store takes a VM ID from 500-599, the next free hundred after the desktop range (STD-0001, D-0038 rule 2, agent pick)."
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{10,14}$", var.store.name))
    error_message = "The store's name must be a STD-0001 hostname: 11 to 15 characters, a-z and 0-9, starting with a letter."
  }

  validation {
    condition     = var.store.memory_mb >= 2048 && var.store.disk_gb >= 20
    error_message = "The store needs at least 2 GiB of RAM and 20 GB of disk (OpenBao, its Raft data and local snapshots)."
  }
}
