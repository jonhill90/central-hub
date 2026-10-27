# Names other run folders need. They are passed on as plain input variables
# (for example remote-access's var.mgmt_vnet = "mgmt"); see AGENT-PICKS.md.
output "vnet_ids" {
  description = "VNet IDs by name, for example { mgmt = \"mgmt\" }."
  value       = { for k, vnet in proxmox_sdn_vnet.lab : k => vnet.id }
}
