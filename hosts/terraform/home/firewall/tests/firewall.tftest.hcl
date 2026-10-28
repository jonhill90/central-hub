# Offline tests for home/firewall: plans against a mocked provider, so no Proxmox host or token
# is needed (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {}

variables {
  proxmox_node_name      = "examplehv01"
  opnsense_lan_mac       = "02:00:00:00:00:01"
  opnsense_wan_mac       = "02:00:00:00:00:02"
  opnsense_wan_connected = false
  firewall_vm_name       = "popnwdemo01"
}

# net0 is the trunk on vmbr1 and must stay first; WAN stays link-down on a fresh build.
run "fresh_build_keeps_wan_down" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.network_device[0].bridge == "vmbr1"
    error_message = "net0 must be the trunk on vmbr1."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.network_device[1].bridge == "vmbr0" && proxmox_virtual_environment_vm.opnsense.network_device[1].disconnected
    error_message = "net1 (WAN, vmbr0) must stay disconnected while opnsense_wan_connected is false."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.vm_id == 100 && proxmox_virtual_environment_vm.opnsense.pool_id == "firewall"
    error_message = "The firewall must be VM 100 in pool firewall."
  }
}

run "running_lab_connects_wan" {
  command = plan

  variables {
    opnsense_wan_connected = true
  }

  assert {
    condition     = !proxmox_virtual_environment_vm.opnsense.network_device[1].disconnected
    error_message = "net1 must be connected when opnsense_wan_connected is true."
  }
}
