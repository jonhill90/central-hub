# Offline tests for home/k8s-talos: plans against a mocked provider (STD-0005). Made-up values.

mock_provider "proxmox" {
  mock_resource "proxmox_download_file" {
    defaults = {
      id = "local:iso/talos-v1.14.5-ce4c980550dd-metal-amd64.iso"
    }
  }
}

variables {
  proxmox_node_name = "examplehv01"
  node_vnet         = "dev"
  nodes = {
    dtacpdemo01 = { vm_id = 252, role = "control-plane", cores = 2, memory_mb = 4096, disk_gb = 20 }
  }
}

# Talos's Proxmox guide: VirtIO SCSI Single hangs bootstrap (Talos #11173); UEFI with an EFI disk.
run "disk_controller_and_firmware_follow_talos_guide" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.node["dtacpdemo01"].scsi_hardware == "virtio-scsi-pci"
    error_message = "Talos nodes must use VirtIO SCSI, not VirtIO SCSI Single."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["dtacpdemo01"].bios == "ovmf" && length(proxmox_virtual_environment_vm.node["dtacpdemo01"].efi_disk) == 1
    error_message = "Talos nodes must boot UEFI with an EFI disk."
  }
}

# STD-0003: one pinned Talos release with the ISO's checksum, from the pinned schematic.
run "iso_pinned" {
  command = plan

  assert {
    condition     = proxmox_download_file.talos_iso.url == "https://factory.talos.dev/image/ce4c980550dd2ab1b17bbf2b08801c7eb59418eafe8f279833297925d67c7515/v1.14.5/metal-amd64.iso" && length(var.talos_iso_sha256) == 64
    error_message = "The Talos ISO must be one pinned version and schematic with its SHA-256."
  }
}

run "nodes_on_their_vnet_with_role_tag" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.node["dtacpdemo01"].network_device[0].bridge == "dev" && proxmox_virtual_environment_vm.node["dtacpdemo01"].tags == tolist(["talos", "dev", "selfhosted", "control-plane"])
    error_message = "A node must sit on node_vnet and be tagged talos, its VNet and its role."
  }
}
