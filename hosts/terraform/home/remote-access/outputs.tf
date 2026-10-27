output "vm_id" {
  description = "Proxmox ID of the connector container."
  value       = proxmox_virtual_environment_container.ts_connector.vm_id
}
