output "vm_id" {
  description = "The test copy's Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.host.vm_id
}
