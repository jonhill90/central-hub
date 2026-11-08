# Tailnet settings that let a tailnet device (the owner's Mac) use lab names:
# 1. the connector's subnet routes for every lab VLAN are turned on, so the Mac can reach the lab's
#    DNS server and the addresses it answers with;
# 2. split DNS sends the lab names (var.split_dns_names under var.zone) to OPNsense Unbound on the
#    mgmt gateway, which holds the host overrides (role opnsense_lab, tasks/dns.yml).
# The connector itself advertises the same routes (role tailnet_connector); a route is used only
# when it is both advertised there and turned on here.

data "tailscale_device" "connector" {
  hostname = var.connector_hostname
  wait_for = "60s"
}

resource "tailscale_device_subnet_routes" "connector" {
  device_id = data.tailscale_device.connector.node_id
  routes = sort(distinct(concat(
    var.connector_extra_routes,
    [for v in yamldecode(file(var.vlans_file)).lab_vlans : v.cidr],
  )))
}

resource "tailscale_dns_split_nameservers" "lab" {
  for_each = toset(var.split_dns_names)

  domain = "${each.value}.${var.zone}"
  nameservers = [
    cidrhost(one([for v in yamldecode(file(var.vlans_file)).lab_vlans : v.cidr if v.name == var.dns_vlan]), 1),
  ]
}
