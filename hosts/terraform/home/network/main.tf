# SDN for the home lab: one VLAN zone on vmbr1, one VNet per lab VLAN, one /24 subnet per VNet.
# The VLANs come from the one shared VLAN file (var.vlans_file), which Ansible reads too; gateway .1 (OPNsense).
# Proxmox runs no SNAT and no DHCP here; OPNsense routes and hands out addresses. snat is left
# unset (off): setting snat = false made bpg 0.116.0 replace every imported subnet (measured
# 2026-10-26, RUNLOG-2026-10-26.md).

resource "proxmox_sdn_zone_vlan" "lab" {
  id     = "lab"
  bridge = "vmbr1"
  nodes  = [var.proxmox_node_name]
}

resource "proxmox_sdn_vnet" "lab" {
  for_each = { for v in yamldecode(file(var.vlans_file)).lab_vlans : v.name => v }

  id    = each.key
  zone  = proxmox_sdn_zone_vlan.lab.id
  tag   = each.value.id
  alias = each.value.alias
}

resource "proxmox_sdn_subnet" "lab" {
  for_each = { for v in yamldecode(file(var.vlans_file)).lab_vlans : v.name => v }

  vnet    = proxmox_sdn_vnet.lab[each.key].id
  cidr    = each.value.cidr
  gateway = cidrhost(each.value.cidr, 1)
}

# Applies pending SDN changes (PUT /cluster/sdn), like the GUI's Apply button.
# The provider marks this resource EXPERIMENTAL.
resource "proxmox_sdn_applier" "lab" {
  depends_on = [
    proxmox_sdn_zone_vlan.lab,
    proxmox_sdn_vnet.lab,
    proxmox_sdn_subnet.lab,
  ]

  lifecycle {
    replace_triggered_by = [
      proxmox_sdn_zone_vlan.lab,
      proxmox_sdn_vnet.lab,
      proxmox_sdn_subnet.lab,
    ]
  }
}
