# The agent jumpbox (J1 of the jumpbox rehearsal, research RB-0179): one AlmaLinux 10 VM on which
# agents run Claude Code Remote Control, with their own narrow keys and hard deny rules.
# The owner chose on 2026-11-10 to grow J1 into this box (8 GiB RAM, 40 GB disk) rather than build
# a new VM. The VM was first made by the rehearsal kit; its state is moved here, not re-created
# (docs/runbooks/grow-the-agent-jumpbox.md). What runs inside it is not done here.
# Exit: tofu destroy with this folder's state, after `claude auth logout` on the box.

resource "proxmox_virtual_environment_vm" "jumpbox" {
  node_name = var.proxmox_node_name
  vm_id     = var.jumpbox.vm_id
  name      = var.jumpbox.name
  tags      = ["almalinux", var.vnet, "jumpbox"]

  on_boot = true
  started = true

  clone {
    vm_id = var.template_vm_id
    full  = true
  }

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  cpu {
    type  = "host"
    cores = var.jumpbox.cores
  }

  memory {
    dedicated = var.jumpbox.memory_mb
    floating  = 0
  }

  agent {
    enabled = true
  }

  serial_device {
    device = "socket"
  }

  # Grows in place; Proxmox can't shrink a disk.
  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = var.jumpbox.disk_gb
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = var.vnet
    model  = "virtio"
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${var.jumpbox.address}/24"
        gateway = cidrhost([for v in yamldecode(file(var.vlans_file)).lab_vlans : v.cidr if v.name == var.vnet][0], 1)
      }
    }

    dns {
      servers = [cidrhost([for v in yamldecode(file(var.vlans_file)).lab_vlans : v.cidr if v.name == var.vnet][0], 1)]
    }

    user_account {
      username = var.admin_user
      keys     = [var.ssh_public_key]
    }
  }
}
