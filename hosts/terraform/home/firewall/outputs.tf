output "vm_id" {
  description = "Proxmox VM ID of the firewall."
  value       = proxmox_virtual_environment_vm.opnsense.vm_id
}
