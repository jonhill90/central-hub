output "node_vm_ids" {
  description = "VM IDs of the nodes, by hostname."
  value       = { for k, vm in proxmox_virtual_environment_vm.node : k => vm.vm_id }
}

output "node_ipv4_addresses" {
  description = "Addresses the guest agent reports, by hostname: the maintenance-mode DHCP address talosctl apply-config --insecure needs. Private: do not paste into the repository."
  value       = { for k, vm in proxmox_virtual_environment_vm.node : k => vm.ipv4_addresses }
}
