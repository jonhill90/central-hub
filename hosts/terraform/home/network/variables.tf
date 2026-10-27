# Variables with no default are private values. They are filled from the secret store at apply
# time (for example as TF_VAR_<name> environment variables) and never written in this repository.

variable "proxmox_node_name" {
  description = "Name of the Proxmox node. Private: from the secret store."
  type        = string
}

variable "vlans_file" {
  description = "Path to the place's shared VLAN file, which Ansible reads too (the owner, 2026-10-26 06:08 UTC: one data file). For home: ../../../ansible/inventories/home/group_vars/all/vlans.yml. Each entry in lab_vlans has id, name, alias and cidr. No default."
  type        = string
}
