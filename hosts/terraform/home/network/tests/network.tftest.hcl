# Offline tests for home/network: a plan against a mocked provider, so no Proxmox host or token is
# needed. Run from this folder: tofu init -backend=false && tofu test (STD-0005).

mock_provider "proxmox" {}

variables {
  proxmox_node_name = "examplehv01" # made up (STD-0001 shape), as in the *.example files
  vlans_file        = "../../../ansible/inventories/home/group_vars/all/vlans.yml"
}

run "one_vnet_per_vlan" {
  command = plan

  assert {
    condition     = length(proxmox_sdn_vnet.lab) == length(yamldecode(file(var.vlans_file)).lab_vlans)
    error_message = "Every VLAN in the shared VLAN file needs exactly one VNet."
  }

  assert {
    condition     = alltrue([for v in yamldecode(file(var.vlans_file)).lab_vlans : proxmox_sdn_vnet.lab[v.name].tag == v.id])
    error_message = "Each VNet's tag must be its VLAN ID from the shared VLAN file."
  }
}

run "gateway_is_dot_one" {
  command = plan

  assert {
    condition     = alltrue([for k, s in proxmox_sdn_subnet.lab : s.gateway == cidrhost(s.cidr, 1)])
    error_message = "Each subnet's gateway must be its .1 address, OPNsense (STD-0002)."
  }

  assert {
    condition     = alltrue([for k, s in proxmox_sdn_subnet.lab : cidrsubnet("10.1.0.0/16", 8, tonumber(split(".", s.cidr)[2])) == s.cidr])
    error_message = "Each subnet must be a /24 in the home range 10.1.0.0/16 (STD-0002)."
  }
}
