# Offline tests for home/ci-runner: a plan against a mocked provider, so no Proxmox host or token is
# needed (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {}

variables {
  proxmox_node_name = "examplehv01"
  vnet              = "dev"
  vlans_file        = "../../../ansible/inventories/home/group_vars/all/vlans.yml"
  template_vm_id    = 9000
  ssh_public_key    = "ssh-ed25519 AAAAexample keys"
  runner            = { name = "dalapdemo01", vm_id = 300, address = "10.1.30.90", cores = 1, memory_mb = 2048, disk_gb = 20 }
}

run "runner_on_dev_in_pool_ci" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.runner.network_device[0].bridge == "dev"
    error_message = "The runner must sit on VNet dev."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.runner.pool_id == "ci"
    error_message = "The runner must be created in pool ci, the only pool the agents' user may create it in."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.runner.clone[0].vm_id == 9000
    error_message = "The runner must be cloned from the AlmaLinux template 9000."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.runner.initialization[0].ip_config[0].ipv4[0].gateway == "10.1.30.1"
    error_message = "The gateway must be the dev VLAN's .1 from the shared VLAN file."
  }
}

run "id_outside_the_ci_range_is_refused" {
  command = plan

  variables {
    runner = { name = "dalapdemo01", vm_id = 258, address = "10.1.30.90", cores = 1, memory_mb = 2048, disk_gb = 20 }
  }

  expect_failures = [var.runner]
}

run "name_that_is_not_std_0001_is_refused" {
  command = plan

  variables {
    runner = { name = "ci-runner", vm_id = 300, address = "10.1.30.90", cores = 1, memory_mb = 2048, disk_gb = 20 }
  }

  expect_failures = [var.runner]
}
