# Adopt the records that are already in the zone (STD-0004 Terraform rule 1 allows this file only
# while a folder adopts objects). export-records.sh writes var.import_ids from the live zone.
# Remove this file once the first apply has imported them, so a plan on an empty zone stays clean.
import {
  for_each = var.import_ids
  to       = cloudflare_dns_record.this[each.key]
  id       = each.value
}
