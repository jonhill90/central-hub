output "vm_id" {
  description = "The runner's Proxmox VM ID."
  value       = proxmox_virtual_environment_vm.runner.vm_id
}
