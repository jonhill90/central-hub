# Every DNS record of the public zone at Cloudflare, so the zone is changed by a plan someone can
# read instead of in the dashboard or by a script. The records are a private input
# (var.records); this file is only the shape. A record removed from var.records is deleted on
# the next apply.

# The zone, looked up by name, so its ID is never written here.
data "cloudflare_zone" "this" {
  filter = {
    name = var.zone_name
  }
}

resource "cloudflare_dns_record" "this" {
  for_each = var.records

  zone_id = data.cloudflare_zone.this.id
  type    = each.value.type
  name    = each.value.name
  content = each.value.content
  ttl     = each.value.ttl
  proxied = each.value.proxied
  # Cloudflare keeps an SRV record's priority both in data and at the top level, so an SRV entry
  # without a top-level priority takes it from data (else an imported SRV record plans a change).
  priority = each.value.priority != null ? each.value.priority : (each.value.data != null ? each.value.data.priority : null)
  comment  = each.value.comment
  data     = each.value.data
}
