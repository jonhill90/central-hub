# Counts only: the names and values are private and stay in the state and the records file.
output "record_count" {
  description = "How many records this folder manages."
  value       = length(cloudflare_dns_record.this)
}

output "record_types" {
  description = "How many records of each type."
  value       = { for t in distinct([for r in values(var.records) : r.type]) : t => length([for r in values(var.records) : r if r.type == t]) }
}
