# Variables with no default are private values. They are filled from the git-ignored home.tfvars
# or as TF_VAR_<name> environment variables, and never written in this repository.

variable "vlans_file" {
  description = "Path to the place's shared VLAN file, which Ansible, home/network and home/tailnet read too (the owner, 2026-10-26 06:08 UTC: one data file). For home: ../../../ansible/inventories/home/group_vars/all/vlans.yml. No default."
  type        = string
}

variable "proxmox_host_address" {
  description = "The Proxmox host's home LAN address, which the connector advertises as a /32 (home/tailnet's connector_extra_routes). Private: it stays out of this public repository (CLAUDE.md rule 4). No default (STD-0004 rule 2)."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{1,3}(\\.[0-9]{1,3}){3}$", var.proxmox_host_address)) && can(cidrhost("${var.proxmox_host_address}/32", 0))
    error_message = "proxmox_host_address must be one IPv4 address, with no prefix length."
  }
}
