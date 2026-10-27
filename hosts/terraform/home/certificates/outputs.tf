# The token's value is never an output; it is only in the token file (and in the state).
output "token_id" {
  description = "Cloudflare's ID of the cert-manager token."
  value       = cloudflare_account_token.cert_manager.id
}

output "token_expires_on" {
  description = "When the current token stops working."
  value       = cloudflare_account_token.cert_manager.expires_on
}

output "token_replace_after" {
  description = "The first apply after this time replaces the token."
  value       = time_rotating.token.rotation_rfc3339
}
