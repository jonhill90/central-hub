# Offline tests for home/certificates: every provider is mocked, so no Cloudflare token is needed,
# nothing is made at Cloudflare and no token file is written (STD-0005). Values are made up, as
# in home.tfvars.example. The runs use apply, which with mocked providers only fills in values.

mock_provider "cloudflare" {
  mock_data "cloudflare_zone" {
    defaults = {
      id      = "zone0example"
      account = { id = "account0example" }
    }
  }

  # The two zone-scoped groups the token needs, and an account-scoped group with the same name
  # as one of them, which must not be picked.
  mock_data "cloudflare_account_api_token_permission_groups_list" {
    defaults = {
      result = [
        { id = "group-dns-write", name = "DNS Write", scopes = ["com.cloudflare.api.account.zone"] },
        { id = "group-zone-read", name = "Zone Read", scopes = ["com.cloudflare.api.account.zone"] },
        { id = "group-dns-write-account", name = "DNS Write", scopes = ["com.cloudflare.api.account"] },
      ]
    }
  }
}

mock_provider "time" {}
mock_provider "local" {}

variables {
  zone_name  = "example.com"
  token_file = "~/.config/central-hub/cloudflare-dns01-token.txt"
}

# Spec c1-way-in-for-web-traffic, manual criterion 3: the DNS-01 token can change only the one
# zone's records, as far as the DNS host allows.
run "token_limited_to_one_zone" {
  assert {
    condition     = length(cloudflare_account_token.cert_manager.policies) == 1
    error_message = "The token must have exactly one policy."
  }

  assert {
    condition     = jsondecode(cloudflare_account_token.cert_manager.policies[0].resources) == { "com.cloudflare.api.account.zone.zone0example" = "*" }
    error_message = "The token's policy must name only the one zone."
  }

  assert {
    condition     = toset([for g in cloudflare_account_token.cert_manager.policies[0].permission_groups : g.id]) == toset(["group-dns-write", "group-zone-read"])
    error_message = "The token must have only the zone-scoped DNS Write and Zone Read groups."
  }

  assert {
    condition     = cloudflare_account_token.cert_manager.condition == null
    error_message = "With request_ip_in empty, the token must have no IP condition."
  }
}

# The token file is private to the operator: 0600 in a 0700 folder.
run "token_file_private" {
  assert {
    condition     = local_sensitive_file.token.file_permission == "0600" && local_sensitive_file.token.directory_permission == "0700"
    error_message = "The token file must be 0600 in a 0700 folder."
  }
}

# The rotation clock runs out token_renew_days before the token expires.
run "renews_before_expiry" {
  assert {
    condition     = time_rotating.token.rotation_days == 76
    error_message = "With the defaults (90-day token, renew 14 days before), the clock must run 76 days."
  }
}

# With a permission group missing, the precondition stops the run before any token is made.
run "missing_permission_group_stops" {
  override_data {
    target = data.cloudflare_account_api_token_permission_groups_list.all
    values = {
      result = [
        { id = "group-dns-write", name = "DNS Write", scopes = ["com.cloudflare.api.account.zone"] },
      ]
    }
  }

  expect_failures = [cloudflare_account_token.cert_manager]
}
