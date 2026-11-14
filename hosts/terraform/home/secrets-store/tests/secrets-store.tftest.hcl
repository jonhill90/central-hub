# Offline tests for home/secrets-store: a plan against a mocked provider, so no Proxmox host or token
# is needed (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {}

variables {
  proxmox_node_name = "examplehv01"
  vnet              = "dev"
  vlans_file        = "../../../ansible/inventories/home/group_vars/all/vlans.yml"
  template_vm_id    = 9001
  ssh_public_key    = "ssh-ed25519 AAAAexample keys"
  store             = { name = "daldapdemo01", vm_id = 550, address = "10.1.30.92", cores = 2, memory_mb = 2048, disk_gb = 20 }
}

run "store_on_dev_in_pool_dev" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.store.network_device[0].bridge == "dev"
    error_message = "The dev store must sit on VNet dev."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.store.pool_id == "dev"
    error_message = "The dev store is cloned into pool dev, where the agents' token holds its rights."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.store.clone[0].vm_id == 9001
    error_message = "The store must be cloned from the agents' template 9001."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.store.initialization[0].ip_config[0].ipv4[0].gateway == "10.1.30.1"
    error_message = "The gateway must be the dev VLAN's .1 from the shared VLAN file."
  }
}

run "id_outside_the_store_range_is_refused" {
  command = plan

  variables {
    store = { name = "daldapdemo01", vm_id = 258, address = "10.1.30.92", cores = 2, memory_mb = 2048, disk_gb = 20 }
  }

  expect_failures = [var.store]
}

run "name_that_is_not_std_0001_is_refused" {
  command = plan

  variables {
    store = { name = "openbao", vm_id = 550, address = "10.1.30.92", cores = 2, memory_mb = 2048, disk_gb = 20 }
  }

  expect_failures = [var.store]
}
