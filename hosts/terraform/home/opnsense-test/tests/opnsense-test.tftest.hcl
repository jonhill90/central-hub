# Offline tests for home/opnsense-test: plans against a mocked provider, so no Proxmox host or token is
# needed (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:iso/opnsense-test-257-seed.iso"
    }
  }
}

variables {
  proxmox_node_name = "examplehv01"
  vnet              = "dev"
  seed_iso_path     = "/tmp/example-seed.iso"
  seed_iso_sha256   = "1111111111111111111111111111111111111111111111111111111111111111"
  image_path        = "/tmp/example.qcow2"
  image_sha256      = "0000000000000000000000000000000000000000000000000000000000000000"
  vm                = { name = "daldopdemo01", vm_id = 257, cores = 1, memory_mb = 3072, disk_gb = 16 }
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

run "boots_from_the_image_with_the_seed_attached" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.opnsense.cdrom[0].interface == "ide2" && proxmox_virtual_environment_vm.opnsense.boot_order == tolist(["scsi0"])
    error_message = "The seed ISO sits on ide2 and the VM boots from the imported disk, never from the ISO."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.opnsense.initialization) == 0
    error_message = "No Proxmox cloud-init drive: FreeBSD 14.3's nuageinit ignores its network-config, so the seed ISO carries the address."
  }

  assert {
    condition     = proxmox_virtual_environment_file.seed.content_type == "iso" && proxmox_virtual_environment_file.seed.source_file[0].checksum == var.seed_iso_sha256
    error_message = "The seed is uploaded through the API as an ISO, checked against the hash the wrapper measured."
  }
}

run "refuses_a_bad_seed_hash" {
  command = plan

  variables {
    seed_iso_sha256 = "not-a-hash"
  }

  expect_failures = [var.seed_iso_sha256]
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
    vm = { name = "daldopdemo01", vm_id = 250, cores = 1, memory_mb = 3072, disk_gb = 16 }
  }

  expect_failures = [var.vm]
}

run "refuses_less_than_3_gib" {
  command = plan

  variables {
    vm = { name = "daldopdemo01", vm_id = 257, cores = 1, memory_mb = 2048, disk_gb = 16 }
  }

  expect_failures = [var.vm]
}
