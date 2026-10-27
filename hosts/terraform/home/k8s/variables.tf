# Variables with no default are private values or place values. Private ones are filled at apply
# time and never written in this repository; set them in the git-ignored home.tfvars.

variable "proxmox_node_name" {
  description = "Name of the Proxmox node. Private."
  type        = string
}

variable "vlans_file" {
  description = "Path to the place's shared VLAN file (the same one home/network and Ansible read). For home: ../../../ansible/inventories/home/group_vars/all/vlans.yml. No default."
  type        = string
}

variable "node_vnet" {
  description = "The VNet the nodes sit on (STD-0002: prod is VLAN 10)."
  type        = string
  default     = "prod"
}

variable "almalinux_image_url" {
  description = "AlmaLinux 10 GenericCloud qcow2 image, pinned to one build (the owner said yes to a pinned image on 2026-10-26 at 07:32 UTC). 10.2-20261012.0 was released 2026-10-12, two weeks before it was pinned (STD-0003 rule 1)."
  type        = string
  default     = "https://repo.almalinux.org/almalinux/10/cloud/x86_64/images/AlmaLinux-10-GenericCloud-10.2-20261012.0.x86_64.qcow2"
}

variable "almalinux_image_sha256" {
  description = "SHA-256 of that build, from the repository's CHECKSUM file."
  type        = string
  default     = "cbee4726fc0f5a60694bb4f289003cc221e715dfbacebcce76b54daf386d8eca"
}

variable "node_admin_user" {
  description = "The admin user cloud-init creates on each node, for Ansible."
  type        = string
  default     = "almalinux"
}

variable "node_ssh_public_key" {
  description = "Public SSH key for node_admin_user. No default."
  type        = string
}

variable "nodes" {
  description = "One entry per node, keyed by its STD-0001 hostname. address is the node's fixed address on node_vnet, without /24. Private: set it in the git-ignored home.tfvars."
  type = map(object({
    vm_id     = number
    role      = string # control-plane or worker
    cores     = number
    memory_mb = number
    disk_gb   = number
    address   = string
  }))
}
