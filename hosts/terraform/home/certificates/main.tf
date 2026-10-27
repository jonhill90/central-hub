# The Cloudflare API token cert-manager uses for its Let's Encrypt DNS-01 challenge (BUILD-PATH
# S12, role k8s_certs). It replaces the token made by hand in the dashboard: `tofu apply` makes it
# and writes it to the file the Ansible inventory names, then `playbooks/k8s-certs.yml --tags
# issue` puts it in the cluster. Permissions as cert-manager's Cloudflare page lists them
# (Zone / DNS / Edit and Zone / Zone / Read), limited to the one zone instead of all zones.
#
# An account-owned token (cloudflare_account_token), made with the account-owned bootstrap token
# (Account API Tokens Write on the account, plus Zone Read on the one zone so the zone and its
# account are looked up by name). It outlives any one user's membership of the account.

# The zone, looked up by name, so its ID is never written here.
data "cloudflare_zone" "this" {
  filter = {
    name = var.zone_name
  }
}

# Every permission group an account token can use. Filtered here by exact name and scope instead
# of with the data source's own name filter, whose value the API wants URL-encoded.
data "cloudflare_account_api_token_permission_groups_list" "all" {
  account_id = local.account_id
}

locals {
  account_id = data.cloudflare_zone.this.account.id
  zone_scope = "com.cloudflare.api.account.zone"

  # API names of the dashboard's "Zone / DNS / Edit" and "Zone / Zone / Read". one() stops the run
  # if a name matches more than one zone-scoped group.
  permission_group_ids = {
    for name in ["DNS Write", "Zone Read"] : name => one([
      for g in data.cloudflare_account_api_token_permission_groups_list.all.result : g.id
      if g.name == name && contains(g.scopes, local.zone_scope)
    ])
  }
}

# The rotation clock. It starts when the token is made and runs out token_renew_days before the
# token expires; the first apply after that makes a new clock, and with it a new token.
resource "time_rotating" "token" {
  rotation_days = var.token_lifetime_days - var.token_renew_days
}

resource "cloudflare_account_token" "cert_manager" {
  account_id = local.account_id
  name       = var.token_name

  policies = [{
    effect = "allow"
    permission_groups = [
      for name in ["DNS Write", "Zone Read"] : { id = local.permission_group_ids[name] }
    ]
    resources = jsonencode({
      "${local.zone_scope}.${data.cloudflare_zone.this.id}" = "*"
    })
  }]

  # Fixed from the clock's start, so a re-apply gives the same value and changes nothing.
  expires_on = timeadd(time_rotating.token.rfc3339, "${var.token_lifetime_days * 24}h")

  # Off by default: see var.request_ip_in.
  condition = length(var.request_ip_in) > 0 ? { request_ip = { in = var.request_ip_in } } : null

  lifecycle {
    # A new clock means a new token (a new secret value), not the old token with a later expiry.
    replace_triggered_by = [time_rotating.token]
    # The new token exists before the old one is deleted.
    create_before_destroy = true

    precondition {
      condition     = alltrue([for id in values(local.permission_group_ids) : id != null])
      error_message = "Permission group \"DNS Write\" or \"Zone Read\" (scope com.cloudflare.api.account.zone) was not found, or the bootstrap token can't list permission groups."
    }
  }
}

# The token for Ansible: the file k8s_certs_cloudflare_token_file names, 0600, folder 0700.
# A changed or missing file is written again on the next apply.
resource "local_sensitive_file" "token" {
  filename             = pathexpand(var.token_file)
  content              = cloudflare_account_token.cert_manager.value
  file_permission      = "0600"
  directory_permission = "0700"
}
