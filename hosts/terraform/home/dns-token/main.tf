# The Cloudflare API token that OpenTofu uses to manage the zone's DNS records (run folder
# ../dns). It replaces editing records in the dashboard: `tofu apply` here makes the token and
# writes it to a 0600 file, and ../dns reads that file. Same shape as ../certificates (the
# cert-manager token), with its own token, so each job has its own credential and can be revoked
# on its own.
#
# Permissions: Zone / DNS / Edit and Zone / Zone / Read (API names "DNS Write" and "Zone Read"),
# limited to the one zone. DNS Write also reads records.

# The zone, looked up by name, so its ID is never written here.
data "cloudflare_zone" "this" {
  filter = {
    name = var.zone_name
  }
}

# Every permission group an account token can use, filtered below by exact name and scope.
data "cloudflare_account_api_token_permission_groups_list" "all" {
  account_id = data.cloudflare_zone.this.account.id
}

# The rotation clock: it runs out token_renew_days before the token expires, and the first apply
# after that makes a new token.
resource "time_rotating" "token" {
  rotation_days = var.token_lifetime_days - var.token_renew_days
}

resource "cloudflare_account_token" "dns" {
  account_id = data.cloudflare_zone.this.account.id
  name       = var.token_name

  policies = [{
    effect = "allow"
    permission_groups = [
      for name in ["DNS Write", "Zone Read"] : {
        id = one([
          for g in data.cloudflare_account_api_token_permission_groups_list.all.result : g.id
          if g.name == name && contains(g.scopes, "com.cloudflare.api.account.zone")
        ])
      }
    ]
    resources = jsonencode({
      "com.cloudflare.api.account.zone.${data.cloudflare_zone.this.id}" = "*"
    })
  }]

  # Fixed from the clock's start, so a re-apply gives the same value and changes nothing.
  expires_on = timeadd(time_rotating.token.rfc3339, "${var.token_lifetime_days * 24}h")

  lifecycle {
    replace_triggered_by  = [time_rotating.token]
    create_before_destroy = true

    precondition {
      condition = length([
        for g in data.cloudflare_account_api_token_permission_groups_list.all.result : g.id
        if contains(["DNS Write", "Zone Read"], g.name) && contains(g.scopes, "com.cloudflare.api.account.zone")
      ]) == 2
      error_message = "Permission group \"DNS Write\" or \"Zone Read\" (scope com.cloudflare.api.account.zone) was not found, or the bootstrap token can't list permission groups."
    }
  }
}

# The token for ../dns: the file its var.token_file names, 0600, folder 0700.
resource "local_sensitive_file" "token" {
  filename             = pathexpand(var.token_file)
  content              = cloudflare_account_token.dns.value
  file_permission      = "0600"
  directory_permission = "0700"
}
