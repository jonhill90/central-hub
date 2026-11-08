# A Talos Linux cluster's node VMs, for the R4 rehearsal beside c1. Not a clone of c1's AlmaLinux
# template: Talos boots its own ISO and is configured by talosctl, with no cloud-init user.
# Settings follow Talos's Proxmox guide (siderolabs/docs public/talos/v1.14/
# platform-specific-installations/virtualized-platforms/proxmox.mdx:66-80), where it differs from
# home/k8s: VirtIO SCSI, not VirtIO SCSI Single, which hangs Talos's bootstrap (Talos #11173), and
# UEFI (ovmf) with an EFI disk. What runs inside the nodes is talosctl's job, not this.

resource "proxmox_download_file" "talos_iso" {
  node_name          = var.proxmox_node_name
  datastore_id       = "local"
  content_type       = "iso"
  url                = "https://factory.talos.dev/image/${var.talos_schematic_id}/${var.talos_version}/metal-amd64.iso"
  file_name          = "talos-${var.talos_version}-${substr(var.talos_schematic_id, 0, 12)}-metal-amd64.iso"
  checksum           = var.talos_iso_sha256
  checksum_algorithm = "sha256"
  overwrite          = false
}

resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  node_name = var.proxmox_node_name
  vm_id     = each.value.vm_id
  name      = each.key
  pool_id   = "k8s"
  tags      = ["talos", var.node_vnet, "selfhosted", each.value.role]

  on_boot = true
  started = true

  machine       = "q35"
  bios          = "ovmf"
  scsi_hardware = "virtio-scsi-pci"

  operating_system {
    type = "l26"
  }

  cpu {
    type  = "host"
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory_mb
    floating  = 0
  }

  # The ISO carries the qemu-guest-agent extension, so the agent reports the DHCP address that
  # talosctl apply-config --insecure needs.
  agent {
    enabled = true
  }

  efi_disk {
    datastore_id = "local-lvm"
    type         = "4m"
  }

  cdrom {
    file_id   = proxmox_download_file.talos_iso.id
    interface = "ide2"
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = each.value.disk_gb
    cache        = "writethrough"
    discard      = "on"
  }

  boot_order = ["scsi0", "ide2"]

  network_device {
    bridge = var.node_vnet
    model  = "virtio"
  }
}
