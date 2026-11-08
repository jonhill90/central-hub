output "routes" {
  description = "The connector's subnet routes that are turned on."
  value       = tailscale_device_subnet_routes.connector.routes
}

output "dns_server" {
  description = "The lab DNS server the split DNS names go to (the mgmt gateway, .1)."
  value       = one(distinct([for d in tailscale_dns_split_nameservers.lab : one(d.nameservers)]))
}

output "split_dns_domains" {
  description = "The split DNS domains, one per name in var.split_dns_names."
  value       = sort([for d in tailscale_dns_split_nameservers.lab : d.domain])
  sensitive   = true
}
