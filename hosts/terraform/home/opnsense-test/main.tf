# A throwaway OPNsense on VNet dev for the proof of sign-in through Keycloak (TEST-VM design v4, passed by
# Councils A, B and C on 2026-11-17). Its first boot needs no console: it boots the FreeBSD 14.3 cloud
# image with Proxmox cloud-init (the box's SSH key and a static dev address), and the opnsense-test
# wrapper then seeds /conf/config.xml and runs the pinned opnsense-bootstrap over SSH. OPNsense 26.1 is
# built on FreeBSD 14.3 and its boot importer keeps a config.xml that is already there.
# One NIC on dev, no WAN, so it routes nothing. Built only while dev is down, destroyed at the end of
# the proof. Applied from the agent box by the opnsense-test wrapper (docs/runbooks/prove-opnsense-sign-in-on-dev.md).
# Exit: tofu destroy with this folder's state.

locals {
  dev_cidr = [for v in yamldecode(file(var.vlans_file)).lab_vlans : v.cidr if v.name == var.vnet][0]
  gateway  = cidrhost(local.dev_cidr, 1)
}

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

resource "proxmox_virtual_environment_vm" "opnsense" {
  node_name = var.proxmox_node_name
  vm_id     = var.vm.vm_id
  name      = var.vm.name
  pool_id   = var.pool_id
  tags      = ["opnsense", var.vnet, "test"]

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

  network_device {
    bridge = var.vnet
    model  = "virtio"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${var.vm.address}/24"
        gateway = local.gateway
      }
    }

    dns {
      servers = [local.gateway]
    }

    user_account {
      username = var.admin_user
      keys     = [var.ssh_public_key]
    }
  }
}
