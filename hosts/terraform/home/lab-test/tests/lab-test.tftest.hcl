# Offline tests for home/lab-test: plans against a mocked provider, so no Proxmox host or token is needed
# (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {
  mock_resource "proxmox_virtual_environment_file" {
    defaults = {
      id = "local:iso/lab-test-256-pve-auto.iso"
    }
  }
}

variables {
  proxmox_node_name    = "examplehv01"
  vnet                 = "dev"
  installer_iso_path   = "/tmp/example-pve-auto.iso"
  installer_iso_sha256 = "2222222222222222222222222222222222222222222222222222222222222222"
  vm                   = { name = "ddehvdemo01", vm_id = 256, cores = 2, memory_mb = 6144, disk_gb = 32 }
}

run "one_nic_on_dev_in_pool_dev" {
  command = plan

  assert {
    condition     = length(proxmox_virtual_environment_vm.host.network_device) == 1 && proxmox_virtual_environment_vm.host.network_device[0].bridge == "dev"
    error_message = "The test copy has one NIC, on VNet dev."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.host.pool_id == "dev" && proxmox_virtual_environment_vm.host.vm_id == 256
    error_message = "The test copy is VM 256 in pool dev."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.host.on_boot == false
    error_message = "A throwaway VM must not start with the host."
  }

  assert {
    condition     = length(coalesce(proxmox_virtual_environment_vm.host.tags, [])) == 0
    error_message = "The test copy sets no tags: a create's tags are checked on /vms/256, where the agents' token has no right."
  }
}

run "nested_ready_and_sized" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.host.cpu[0].type == "host"
    error_message = "CPU type host, so the copy sees the virtualisation flags its own guests need."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.host.memory[0].dedicated == 6144 && proxmox_virtual_environment_vm.host.memory[0].floating == 0
    error_message = "The copy gets 6144 MiB, with no ballooning."
  }
}

run "installs_from_the_prepared_iso" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.host.boot_order == tolist(["scsi0", "ide2"]) && proxmox_virtual_environment_vm.host.cdrom[0].interface == "ide2"
    error_message = "The empty disk boots first, so the first boot falls through to the installer on ide2 and later boots start the installed system."
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.host.initialization) == 0
    error_message = "No Proxmox cloud-init drive: the installer's answer file carries the address and keys."
  }

  assert {
    condition     = proxmox_virtual_environment_file.installer.content_type == "iso" && proxmox_virtual_environment_file.installer.source_file[0].checksum == var.installer_iso_sha256
    error_message = "The installer is uploaded through the API as an ISO, checked against the hash the wrapper measured."
  }

  assert {
    condition     = proxmox_virtual_environment_file.installer.source_file[0].file_name == "lab-test-256-pve-auto-222222222222.iso"
    error_message = "Each installer ISO is a new file named by its hash, so a new one never needs a delete the token can't make."
  }
}

run "refuses_a_bad_iso_hash" {
  command = plan

  variables {
    installer_iso_sha256 = "not-a-hash"
  }

  expect_failures = [var.installer_iso_sha256]
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
    vm = { name = "ddehvdemo01", vm_id = 257, cores = 2, memory_mb = 6144, disk_gb = 32 }
  }

  expect_failures = [var.vm]
}

run "refuses_less_than_6_gib" {
  command = plan

  variables {
    vm = { name = "ddehvdemo01", vm_id = 256, cores = 2, memory_mb = 5120, disk_gb = 32 }
  }

  expect_failures = [var.vm]
}
