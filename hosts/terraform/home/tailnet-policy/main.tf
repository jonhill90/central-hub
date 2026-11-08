# The tailnet policy file (who may reach what), kept in this public repository with tags and the
# lab's address ranges only; the one private value, the Proxmox host's address, is filled in at
# apply time (the owner's yes of 2026-10-17 at 20:23 UTC: tags only, secrets filled in at apply
# time, a leak scan on every PR). The policy itself is policy.hujson.tftpl.
#
# overwrite_existing_content stays false, so a first apply against a tailnet whose policy was
# edited by hand stops with an error instead of replacing it. Adopt the live policy first with
# `tofu import tailscale_acl.policy acl`, then read the plan's diff before any apply (README).

resource "tailscale_acl" "policy" {
  acl = templatefile("${path.module}/policy.hujson.tftpl", {
    proxmox_host_address = var.proxmox_host_address
    lab_ranges           = [for v in yamldecode(file(var.vlans_file)).lab_vlans : v.cidr]
  })

  overwrite_existing_content = false
  reset_acl_on_destroy       = false
}
