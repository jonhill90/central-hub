# Offline tests for home/dns: the provider is mocked, so no token is needed and nothing changes at
# Cloudflare (STD-0005). Values are made up, as in the examples.

mock_provider "cloudflare" {
  mock_data "cloudflare_zone" {
    defaults = {
      id = "zone0example"
    }
  }
}

variables {
  zone_name  = "example.com"
  token_file = "./tests/not-a-token.txt"
  records = {
    a-apex    = { type = "A", name = "example.com", content = "192.0.2.10", ttl = 3600 }
    mx-apex-1 = { type = "MX", name = "example.com", content = "mx1.example.net", priority = 5 }
    srv-autodiscover = {
      type = "SRV", name = "_autodiscover._tcp.example.com"
      data = { priority = 0, weight = 0, port = 443, target = "mail.example.net" }
    }
  }
}

# One resource per record, all in the zone found by name, with the values as given.
run "one_resource_per_record" {
  assert {
    condition     = length(cloudflare_dns_record.this) == 3
    error_message = "Each entry of var.records must be one record."
  }

  assert {
    condition     = alltrue([for r in values(cloudflare_dns_record.this) : r.zone_id == "zone0example"])
    error_message = "Every record must be in the zone looked up by name."
  }

  assert {
    condition     = cloudflare_dns_record.this["mx-apex-1"].priority == 5 && cloudflare_dns_record.this["a-apex"].ttl == 3600
    error_message = "Priority and TTL must come from the records file."
  }

  assert {
    condition     = cloudflare_dns_record.this["mx-apex-1"].ttl == 1 && cloudflare_dns_record.this["mx-apex-1"].proxied == false
    error_message = "A record without ttl or proxied must be TTL auto (1) and not proxied."
  }

  assert {
    condition     = cloudflare_dns_record.this["srv-autodiscover"].priority == 0
    error_message = "An SRV record without a top-level priority must take it from data."
  }

  assert {
    condition     = output.record_types == { A = 1, MX = 1, SRV = 1 }
    error_message = "record_types must count the records by type."
  }
}

# A record with both content and data, or neither, stops the plan.
run "content_or_data" {
  command = plan

  variables {
    records = {
      bad = { type = "SRV", name = "_x._tcp.example.com", content = "0 0 443 x.example.net", data = { port = 443 } }
    }
  }

  expect_failures = [var.records]
}
