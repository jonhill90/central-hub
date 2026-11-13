variable "proxmox_node_name" {
  description = "The Proxmox node, same value as home/k8s."
  type        = string
}

variable "vlans_file" {
  description = "Path to the place's shared VLAN file (the same one home/network and Ansible read). For home: ../../../ansible/inventories/home/group_vars/all/vlans.yml. No default."
  type        = string
}

variable "vnet" {
  description = "VNet the desktop sits on, by name from the VLAN file. No default (STD-0004 rule 2)."
  type        = string
}

variable "template_vm_id" {
  description = "The agents' AlmaLinux 10 template on VNet dev (9001), a copy of the one home/k8s owns, made by home/bootstrap/agent-access.sh."
  type        = number
}

variable "pool_id" {
  description = "Proxmox resource pool the desktop goes in. The agents' token holds its rights on /pool/desktop, which a clone that names the pool needs and which a teardown doesn't remove (the same as pool dev, #231). null leaves it out of any pool."
  type        = string
  default     = "desktop"
}

variable "admin_user" {
  description = "Login user with sudo, made by cloud-init. Ansible reaches the desktop as this user."
  type        = string
  default     = "admin"
}

variable "ssh_public_key" {
  description = "Public half of the SSH key the agent box's keys user configures the desktop with once. The role removes it from the VM at the end of that first run, so the agents keep no login on the desktop."
  type        = string
}

variable "desktop" {
  description = "The desktop VM. Name (STD-0001) and address are private values set only in the git-ignored tfvars."
  type = object({
    name      = string
    vm_id     = number
    address   = string
    cores     = number
    memory_mb = number
    disk_gb   = number
  })

  validation {
    condition     = var.desktop.vm_id >= 400 && var.desktop.vm_id <= 499
    error_message = "A desktop takes a VM ID from 400-499, the next free hundred after the CI range (STD-0001, agent pick)."
  }

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{10,14}$", var.desktop.name))
    error_message = "The desktop's name must be a STD-0001 hostname: 11 to 15 characters, a-z and 0-9, starting with a letter."
  }

  validation {
    condition     = var.desktop.memory_mb >= 4096 && var.desktop.disk_gb >= 30
    error_message = "The desktop needs at least 4 GiB of RAM and 30 GB of disk (Xfce, a browser and xrdp)."
  }
}
