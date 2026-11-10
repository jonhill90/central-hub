output "vm_id" {
  description = "The jumpbox's Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.jumpbox.vm_id
}
