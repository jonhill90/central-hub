variable "proxmox_node_name" {
  description = "The Proxmox node, same value as home/k8s."
  type        = string
}

variable "vlans_file" {
  description = "Path to the place's shared VLAN file (the same one home/network and Ansible read). For home: ../../../ansible/inventories/home/group_vars/all/vlans.yml. No default."
  type        = string
}

variable "vnet" {
  description = "VNet the jumpbox sits on, by name from the VLAN file. No default (STD-0004 rule 2)."
  type        = string
}

variable "template_vm_id" {
  description = "The AlmaLinux 10 VM template home/k8s owns (9000). Used only if the VM is ever created anew."
  type        = number
}

variable "admin_user" {
  description = "Login user with sudo, made by cloud-init."
  type        = string
  default     = "admin"
}

variable "ssh_public_key" {
  description = "Public half of the admin SSH key."
  type        = string
}

variable "jumpbox" {
  description = "The jumpbox VM. Name (STD-0001) and address are private values set only in the git-ignored tfvars."
  type = object({
    name      = string
    vm_id     = number
    address   = string
    cores     = number
    memory_mb = number
    disk_gb   = number
  })

  validation {
    condition     = var.jumpbox.memory_mb >= 4096 && var.jumpbox.disk_gb >= 40
    error_message = "The agent jumpbox needs at least 4 GiB of RAM (its size in the rehearsal) and 40 GB of disk. Set the RAM from the measurement in docs/runbooks/grow-the-agent-jumpbox.md step 8."
  }
}
