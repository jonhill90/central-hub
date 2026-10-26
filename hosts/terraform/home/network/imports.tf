# The lab already exists (built by hand and by script). These blocks adopt the running objects
# into state on the first plan instead of creating new ones. Untested: run `tofu plan` first and
# read every proposed change before any apply.

import {
  to = proxmox_sdn_zone_vlan.lab
  id = "lab"
}

import {
  for_each = { for v in yamldecode(file(var.vlans_file)).lab_vlans : v.name => v }
  to       = proxmox_sdn_vnet.lab[each.key]
  id       = each.key
}

import {
  for_each = { for v in yamldecode(file(var.vlans_file)).lab_vlans : v.name => v }
  to       = proxmox_sdn_subnet.lab[each.key]
  id       = "${each.key}/lab-${replace(each.value.cidr, "/", "-")}"
}
