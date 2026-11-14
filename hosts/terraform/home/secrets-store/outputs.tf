output "vm_id" {
  description = "The secrets store's Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.store.vm_id
}
