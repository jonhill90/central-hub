# The token's value is never an output; it is only in the token file (and in the state).
output "token_id" {
  description = "Cloudflare's ID of the DNS token."
  value       = cloudflare_account_token.dns.id
}

output "token_expires_on" {
  description = "When the current token stops working."
  value       = cloudflare_account_token.dns.expires_on
}

output "token_replace_after" {
  description = "The first apply after this time replaces the token."
  value       = time_rotating.token.rotation_rfc3339
}
