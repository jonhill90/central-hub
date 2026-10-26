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

variable "firewall_vm_name" {
  description = "Proxmox VM name of the firewall, an STD-0001 hostname (Jon 2026-10-26 06:06 UTC: OS code op, role nw). No default: the real name stays out of this public repository (CLAUDE.md rule 4); set it in the git-ignored home.tfvars."
  type        = string
}
