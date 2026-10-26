output "node_vm_ids" {
  description = "VM IDs of the nodes, by hostname."
  value       = { for k, vm in proxmox_virtual_environment_vm.node : k => vm.vm_id }
}
