# Private values have no default. The zone name and token path go in the git-ignored home.tfvars;
# the records go in the git-ignored home.records.tfvars.json, which export-records.sh writes from
# the live zone the first time and which is edited by hand after that.

variable "zone_name" {
  description = "The public DNS zone at Cloudflare. Private. No default."
  type        = string
}

variable "token_file" {
  description = "The 0600 file with the DNS token from ../dns-token (its token_file). No default."
  type        = string
}

variable "records" {
  description = "Every record in the zone, by a stable key such as \"a-grafana\" or \"mx-apex-1\". A record left out of this map is deleted on apply; a new key is created. Private. No default."
  type = map(object({
    type     = string
    name     = string           # full name, as Cloudflare shows it (the apex is the zone name itself)
    content  = optional(string) # every type except SRV, CAA and the other types that use data
    ttl      = optional(number, 1)
    proxied  = optional(bool, false)
    priority = optional(number) # MX and URI
    comment  = optional(string)
    data = optional(object({ # SRV and CAA
      priority = optional(number)
      weight   = optional(number)
      port     = optional(number)
      target   = optional(string)
      flags    = optional(number)
      tag      = optional(string)
      value    = optional(string)
    }))
  }))

  validation {
    condition     = alltrue([for r in values(var.records) : (r.content == null) != (r.data == null)])
    error_message = "Each record needs exactly one of content or data."
  }
}

variable "import_ids" {
  description = "Only while adopting the zone (imports.tf): record key to \"<zone id>/<record id>\", as export-records.sh writes it. Empty after the adoption is applied."
  type        = map(string)
  default     = {}
}
