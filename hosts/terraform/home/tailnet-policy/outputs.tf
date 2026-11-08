output "policy" {
  description = "The policy as applied. Sensitive: it names the Proxmox host's home LAN address."
  value       = tailscale_acl.policy.acl
  sensitive   = true
}
