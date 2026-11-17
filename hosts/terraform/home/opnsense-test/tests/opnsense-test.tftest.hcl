# Offline tests for home/opnsense-test: plans against a mocked provider, so no Proxmox host or token is
# needed (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:import/FreeBSD-14.3-RELEASE-amd64-BASIC-CLOUDINIT-ufs.qcow2"
    }
  }
}

variables {
  proxmox_node_name = "examplehv01"
  vnet              = "dev"
  vlans_file        = "../../../ansible/inventories/home/group_vars/all/vlans.yml"
  ssh_public_key    = "ssh-ed25519 AAAAexample keys"
  image_path        = "/tmp/example.qcow2"
  image_sha256      = "0000000000000000000000000000000000000000000000000000000000000000"
  vm                = { name = "daldopdemo01", vm_id = 257, address = "10.1.30.57", cores = 1, memory_mb = 3072, disk_gb = 16 }
}

run "one_nic_on_dev_in_pool_dev" {
  command = plan

  assert {
    condition     = length(proxmox_virtual_environment_vm.opnsense.network_device) == 1 && proxmox_virtual_environment_vm.opnsense.network_device[0].bridge == "dev"
    error_message = "The test VM has one NIC, on VNet dev, and no WAN."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.pool_id == "dev" && proxmox_virtual_environment_vm.opnsense.vm_id == 257
    error_message = "The test VM is VM 257 in pool dev."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.on_boot == false
    error_message = "A throwaway VM must not start with the host."
  }
}

run "gateway_and_dns_are_devs_dot_one" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.initialization[0].ip_config[0].ipv4[0].gateway == "10.1.30.1"
    error_message = "The gateway must be dev's .1 address, read from the shared VLAN file."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.initialization[0].dns[0].servers == tolist(["10.1.30.1"])
    error_message = "The DNS server must be dev's .1 address."
  }
}

run "memory_is_the_documented_minimum" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.memory[0].dedicated == 3072
    error_message = "The test VM gets 3072 MiB, OPNsense's documented minimum."
  }
}

run "refuses_prod" {
  command = plan

  variables {
    vnet = "prod"
  }

  expect_failures = [var.vnet]
}

run "refuses_another_vm_id" {
  command = plan

  variables {
    vm = { name = "daldopdemo01", vm_id = 250, address = "10.1.30.57", cores = 1, memory_mb = 3072, disk_gb = 16 }
  }

  expect_failures = [var.vm]
}

run "refuses_less_than_3_gib" {
  command = plan

  variables {
    vm = { name = "daldopdemo01", vm_id = 257, address = "10.1.30.57", cores = 1, memory_mb = 2048, disk_gb = 16 }
  }

  expect_failures = [var.vm]
}
