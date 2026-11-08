# Variables with no default are private values or place values. Private ones are filled at apply
# time and never written in this repository; set them in the git-ignored home.tfvars.

variable "proxmox_node_name" {
  description = "Name of the Proxmox node. Private."
  type        = string
}

variable "node_vnet" {
  description = "The VNet the nodes sit on (STD-0002). No default: a Talos rehearsal cluster sits beside c1, not on prod."
  type        = string
}

variable "talos_version" {
  description = "Talos release the ISO boots (STD-0003: newest release at least two weeks old). v1.14.5 is dated 2026-10-26."
  type        = string
  default     = "v1.14.5"
}

variable "talos_schematic_id" {
  description = "Image Factory schematic with the siderolabs/qemu-guest-agent extension, as Talos's Proxmox guide gives it (siderolabs/docs public/talos/v1.14/platform-specific-installations/virtualized-platforms/proxmox.mdx:53-57)."
  type        = string
  default     = "ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515"
}

variable "talos_iso_sha256" {
  description = "SHA-256 of metal-amd64.iso for that schematic and version, measured by download on 2026-11-08."
  type        = string
  default     = "b2e13d8d79b006bf2a7cc12f2a6c3222586ff804112a4113db2490cb58a751e2"
}

variable "nodes" {
  description = "One entry per node, keyed by its STD-0001 hostname (OS code ta). The nodes boot the Talos ISO into maintenance mode and get their address by DHCP until talosctl apply-config gives them their machine config. Private: set it in the git-ignored home.tfvars."
  type = map(object({
    vm_id     = number
    role      = string # control-plane or worker
    cores     = number
    memory_mb = number
    disk_gb   = number
  }))
}
