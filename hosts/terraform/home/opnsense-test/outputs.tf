output "vm_id" {
  description = "The test VM's Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.opnsense.vm_id
}
