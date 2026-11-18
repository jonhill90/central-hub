# Variables with no default are private values. They are filled from the secret store at apply
# time (for example as TF_VAR_<name> environment variables) and never written in this repository.

variable "proxmox_node_name" {
  description = "Name of the Proxmox node. Private: from the secret store."
  type        = string
}

variable "opnsense_lan_mac" {
  description = "MAC of the OPNsense trunk NIC (net0, on vmbr1). Private: from the secret store."
  type        = string
}

variable "opnsense_wan_mac" {
  description = "MAC of the OPNsense WAN NIC (net1, on vmbr0). The home router reserves an address for it. Private: from the secret store."
  type        = string
}

variable "opnsense_wan_connected" {
  description = "false on a fresh build, so WAN stays link-down until the WAN safety check passes; true for the running lab. No default on purpose: a wrong value cuts the firewall off."
  type        = bool
}

variable "opnsense_image_file_id" {
  description = "Proxmox file ID of the OPNsense nano image to import, for example \"local:import/<image>.img\". Used only when the VM is first created."
  type        = string
  default     = null
}

variable "trunk_bridge" {
  description = "Bridge that carries the lab VLANs to OPNsense net0 (no physical port, VLAN-aware)."
  type        = string
  default     = "vmbr1"
}

variable "wan_bridge" {
  description = "Bridge for WAN (net1). vmbr0, the home LAN, on the real host. The lab test copy gives a bridge with no ports, so its WAN safety check reaches nothing outside the copy (docs/runbooks/build-the-lab-test-copy.md)."
  type        = string
  default     = "vmbr0"

  validation {
    condition     = can(regex("^vmbr[0-9]+$", var.wan_bridge)) && var.wan_bridge != var.trunk_bridge
    error_message = "wan_bridge must be a vmbrN bridge other than the trunk."
  }
}

variable "firewall_vm_name" {
  description = "Proxmox VM name of the firewall, an STD-0001 hostname (the owner, 2026-10-26 06:06 UTC: OS code op, role nw). No default: the real name stays out of this public repository (CLAUDE.md rule 4); set it in the git-ignored home.tfvars."
  type        = string
}
