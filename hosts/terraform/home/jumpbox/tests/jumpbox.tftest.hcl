# Offline tests for home/jumpbox: a plan against a mocked provider, so no Proxmox host or token is
# needed (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {}

variables {
  proxmox_node_name = "examplehv01"
  vnet              = "dev"
  vlans_file        = "../../../ansible/inventories/home/group_vars/all/vlans.yml"
  template_vm_id    = 9000
  ssh_public_key    = "ssh-ed25519 AAAAexample admin"
  jumpbox           = { name = "ddeapdemo01", vm_id = 258, address = "10.1.30.90", cores = 2, memory_mb = 8192, disk_gb = 40 }
}

run "jumpbox_on_dev_with_its_size" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.jumpbox.network_device[0].bridge == "dev"
    error_message = "The jumpbox must sit on VNet dev."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.jumpbox.memory[0].dedicated == 8192 && proxmox_virtual_environment_vm.jumpbox.disk[0].size == 40
    error_message = "The jumpbox must have 8 GiB of RAM and a 40 GB disk."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.jumpbox.initialization[0].ip_config[0].ipv4[0].gateway == "10.1.30.1"
    error_message = "The gateway must be the dev VLAN's .1 from the shared VLAN file."
  }
}

run "too_small_is_refused" {
  command = plan

  variables {
    jumpbox = { name = "ddeapdemo01", vm_id = 258, address = "10.1.30.90", cores = 2, memory_mb = 4096, disk_gb = 20 }
  }

  expect_failures = [var.jumpbox]
}
