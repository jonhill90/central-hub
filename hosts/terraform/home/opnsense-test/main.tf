# A throwaway OPNsense on VNet dev for the proof of sign-in through Keycloak (TEST-VM design v4, passed by
# Councils A, B and C on 2026-11-17). Its first boot needs no console: it boots the FreeBSD 14.3 cloud
# image with a NoCloud seed ISO the wrapper builds (the box's SSH key for root and a static dev
# address), and the wrapper then seeds /conf/config.xml and runs the pinned opnsense-bootstrap over
# SSH. OPNsense 26.1 is built on FreeBSD 14.3 and its boot importer keeps a config.xml that is
# already there.
# Not Proxmox's own cloud-init drive: FreeBSD 14.3's nuageinit reads no network-config file from a
# NoCloud drive, only a `network` key inside cloud-config user-data, and Proxmox writes its address
# to network-config (freebsd-src releng/14.3 libexec/nuageinit/nuageinit, the nocloud branch).
# One NIC on dev, no WAN, so it routes nothing. Built only while dev is down, destroyed at the end of
# the proof. Applied from the agent box by the opnsense-test wrapper (docs/runbooks/prove-opnsense-sign-in-on-dev.md).
# Exit: `opnsense-test destroy`, which destroys the VM and leaves the seed ISO and image files on local
# for the owner (the agents' token cannot delete them).

# The FreeBSD image, checked and unpacked on the box by the wrapper, uploaded through the API.
resource "proxmox_virtual_environment_file" "image" {
  node_name    = var.proxmox_node_name
  datastore_id = "local"
  content_type = "import"

  source_file {
    path      = var.image_path
    file_name = var.image_file_name
    checksum  = var.image_sha256
  }
}

# The NoCloud seed ISO the wrapper built for this VM: meta-data (hostname) and a user-data script that
# runs as root at first boot. Uploaded through the API (Datastore.AllocateTemplate on local). The agents'
# token cannot delete files on local (no Datastore.Allocate), so each seed is named by its hash: a new
# seed is a new file and never needs a delete. The wrapper builds the ISO byte for byte the same from the same
# settings, so `opnsense-test destroy` keeps the seed in the state and the next plan reuses its file; only a
# changed seed is dropped from the state by plan, leaving its old file on local.
resource "proxmox_virtual_environment_file" "seed" {
  node_name    = var.proxmox_node_name
  datastore_id = "local"
  content_type = "iso"

  source_file {
    path      = var.seed_iso_path
    file_name = "opnsense-test-${var.vm.vm_id}-seed-${substr(var.seed_iso_sha256, 0, 12)}.iso"
    checksum  = var.seed_iso_sha256
  }
}

resource "proxmox_virtual_environment_vm" "opnsense" {
  node_name = var.proxmox_node_name
  vm_id     = var.vm.vm_id
  name      = var.vm.name
  pool_id   = var.pool_id
  # No tags. Proxmox checks a create's tags for VM.Config.Options on /vms/257 itself, before the VM is
  # in pool dev (pve-guest-common GuestHelpers.pm assert_tag_permissions: check_vm_perm with no pool),
  # and the agents' token holds its rights on pool dev only (agent pick 196). Proxmox drops a VM's own
  # ACLs when the VM is destroyed, and the apply after the first proof VM's destroy, 2026-11-18 02:29
  # UTC, failed with 403 on /vms/257, VM.Config.Options.

  on_boot = false
  started = true

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  operating_system {
    type = "other"
  }

  cpu {
    type  = "host"
    cores = var.vm.cores
  }

  memory {
    dedicated = var.vm.memory_mb
    floating  = 0
  }

  serial_device {
    device = "socket"
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    import_from  = proxmox_virtual_environment_file.image.id
    size         = var.vm.disk_gb
    iothread     = true
  }

  # The seed: label cidata, read once by nuageinit at first boot. The drive goes with the VM; the ISO
  # file stays on local (see the seed resource).
  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_file.seed.id
  }

  network_device {
    bridge = var.vnet
    model  = "virtio"
  }

}
