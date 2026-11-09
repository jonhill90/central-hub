# Adopt the records that are already in the zone (STD-0004 Terraform rule 1 allows this file only
# while a folder adopts objects). export-records.sh writes var.import_ids from the live zone.
# Remove this file once the first apply has imported them, so a plan on an empty zone stays clean.
# The variable lives here, not in variables.tf, so it goes with this file.
import {
  for_each = var.import_ids
  to       = cloudflare_dns_record.this[each.key]
  id       = each.value
}

variable "import_ids" {
  description = "Only while adopting the zone (imports.tf): record key to \"<zone id>/<record id>\", as export-records.sh writes it. Empty after the adoption is applied."
  type        = map(string)
  default     = {}
}
