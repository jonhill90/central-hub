# Offline tests for home/dns-token: every provider is mocked, so no Cloudflare token is needed,
# nothing is made at Cloudflare and no token file is written (STD-0005). Values are made up, as
# in home.tfvars.example. The runs use apply, which with mocked providers only fills in values.

mock_provider "cloudflare" {
  mock_data "cloudflare_zone" {
    defaults = {
      id      = "zone0example"
      account = { id = "account0example", name = "Example account" }
    }
  }

  # Each object gives every attribute of its schema, as a mock must.
  # The two zone-scoped groups the token needs, and an account-scoped group with the same name
  # as one of them, which must not be picked.
  mock_data "cloudflare_account_api_token_permission_groups_list" {
    defaults = {
      result = [
        { id = "group-dns-write", name = "DNS Write", scopes = ["com.cloudflare.api.account.zone"], category = "dns_and_zones", is_selectable = true },
        { id = "group-zone-read", name = "Zone Read", scopes = ["com.cloudflare.api.account.zone"], category = "dns_and_zones", is_selectable = true },
        { id = "group-dns-write-account", name = "DNS Write", scopes = ["com.cloudflare.api.account"], category = "dns_and_zones", is_selectable = true },
      ]
    }
  }
}

# timeadd() needs a real timestamp from the clock, not a random string.
mock_provider "time" {
  mock_resource "time_rotating" {
    defaults = {
      rfc3339 = "2026-10-27T00:00:00Z"
    }
  }
}
mock_provider "local" {}

variables {
  zone_name            = "example.com"
  bootstrap_token_file = "./tests/not-a-token.txt"
  token_file           = "~/.config/central-hub/cloudflare-dns-records-token.txt"
}

# The DNS token can change only the one zone's records.
run "token_limited_to_one_zone" {
  assert {
    condition     = length(cloudflare_account_token.dns.policies) == 1
    error_message = "The token must have exactly one policy."
  }

  assert {
    condition     = jsondecode(cloudflare_account_token.dns.policies[0].resources) == { "com.cloudflare.api.account.zone.zone0example" = "*" }
    error_message = "The token's policy must name only the one zone."
  }

  assert {
    condition     = toset([for g in cloudflare_account_token.dns.policies[0].permission_groups : g.id]) == toset(["group-dns-write", "group-zone-read"])
    error_message = "The token must have only the zone-scoped DNS Write and Zone Read groups."
  }

}

# The token file is private to the operator: 0600 in a 0700 folder.
run "token_file_private" {
  assert {
    condition     = local_sensitive_file.token.file_permission == "0600" && local_sensitive_file.token.directory_permission == "0700"
    error_message = "The token file must be 0600 in a 0700 folder."
  }
}

# The rotation clock runs out token_renew_days before the token expires, and the token's expiry
# is the clock's start plus its full lifetime.
run "renews_before_expiry" {
  assert {
    condition     = cloudflare_account_token.dns.expires_on == "2027-01-25T00:00:00Z"
    error_message = "The token must expire 90 days after the clock starts."
  }

  assert {
    condition     = time_rotating.token.rotation_days == 76
    error_message = "With the defaults (90-day token, renew 14 days before), the clock must run 76 days."
  }
}

# With a permission group missing, the precondition stops the run before any token is made.
run "missing_permission_group_stops" {
  # Plan, because the precondition stops the plan; expect_failures is checked there.
  command = plan

  override_data {
    target = data.cloudflare_account_api_token_permission_groups_list.all
    values = {
      result = [
        { id = "group-dns-write", name = "DNS Write", scopes = ["com.cloudflare.api.account.zone"], category = "dns_and_zones", is_selectable = true },
      ]
    }
  }

  expect_failures = [cloudflare_account_token.dns]
}
