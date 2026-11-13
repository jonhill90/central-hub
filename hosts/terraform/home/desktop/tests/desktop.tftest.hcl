# Offline tests for home/desktop: a plan against a mocked provider, so no Proxmox host or token is
# needed (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {}

variables {
  proxmox_node_name = "examplehv01"
  vnet              = "dev"
  vlans_file        = "../../../ansible/inventories/home/group_vars/all/vlans.yml"
  template_vm_id    = 9001
  ssh_public_key    = "ssh-ed25519 AAAAexample keys"
  desktop           = { name = "dalapdemo02", vm_id = 400, address = "10.1.30.91", cores = 2, memory_mb = 4096, disk_gb = 30 }
}

run "desktop_on_dev_in_pool_desktop" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.desktop.network_device[0].bridge == "dev"
    error_message = "The desktop must sit on VNet dev."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.desktop.pool_id == "desktop"
    error_message = "The desktop is cloned into pool desktop, where the agents' token holds its rights."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.desktop.clone[0].vm_id == 9001
    error_message = "The desktop must be cloned from the agents' template 9001."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.desktop.initialization[0].ip_config[0].ipv4[0].gateway == "10.1.30.1"
    error_message = "The gateway must be the dev VLAN's .1 from the shared VLAN file."
  }
}

run "id_outside_the_desktop_range_is_refused" {
  command = plan

  variables {
    desktop = { name = "dalapdemo02", vm_id = 258, address = "10.1.30.91", cores = 2, memory_mb = 4096, disk_gb = 30 }
  }

  expect_failures = [var.desktop]
}

run "name_that_is_not_std_0001_is_refused" {
  command = plan

  variables {
    desktop = { name = "desktop", vm_id = 400, address = "10.1.30.91", cores = 2, memory_mb = 4096, disk_gb = 30 }
  }

  expect_failures = [var.desktop]
}
