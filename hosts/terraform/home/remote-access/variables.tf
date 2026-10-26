# Variables with no default are private values. They are filled from the secret store at apply
# time (for example as TF_VAR_<name> environment variables) and never written in this repository.

variable "proxmox_node_name" {
  description = "Name of the Proxmox node. Private: from the secret store."
  type        = string
}

variable "connector_template_file_id" {
  description = "Proxmox file ID of the Debian 13 container template. Used only when the container is first created."
  type        = string
  default     = null
}

variable "connector_eth0_mac" {
  description = "MAC of the connector's eth0 on vmbr0. The home router reserves an address for it. Private: from the secret store."
  type        = string
}

variable "connector_mgmt_address" {
  description = "The connector's address on VNet mgmt, in CIDR form (address/24), no gateway. Private: from the secret store."
  type        = string
}

variable "connector_swap_mb" {
  description = "Swap for the connector container in MB. The running CT 900 has 0 (measured 2026-10-26 by tofu plan after import)."
  type        = number
  default     = 0
}

variable "mgmt_vnet" {
  description = "Name of the SDN VNet for eth1, made by home/network (its output vnet_ids.mgmt)."
  type        = string
  default     = "mgmt"
}

variable "connector_hostname" {
  description = "Hostname of the connector container, an STD-0001 hostname (Jon 2026-10-26 06:06 UTC: role nw). No default: the real name stays out of this public repository (CLAUDE.md rule 4); set it in the git-ignored home.tfvars."
  type        = string
}
