# The agent jumpbox (VM 258 of the jumpbox rehearsal, research RB-0179): one AlmaLinux 10 VM on which
# agents run Claude Code Remote Control, with their own narrow keys and hard deny rules.
# The owner chose on 2026-11-10 to grow VM 258 into this box rather than build a new VM. Its RAM is a
# starting estimate, right-sized from a measurement (docs/runbooks/grow-the-agent-jumpbox.md step 8). The VM was first made by the rehearsal kit; its state is moved here, not re-created
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

  # floating > 0 gives the VM a balloon device. On a q35 machine (no version pinned, so 6.2 or later) Proxmox adds
  # free-page-reporting=on to it (qemu-server src/PVE/QemuServer.pm, the balloon device), so pages the
  # box frees go back to the host. With floating = 0 there was no balloon, and the box's footprint on the host
  # only grew: the dev preflight's free memory fell from 12887 MiB (2026-11-18 01:49 UTC) to 8414 MiB (03:51 UTC)
  # with the box's guest at 763 MiB used and 5787 MiB cache. 4096 is the least the host's auto-ballooning may
  # shrink the box to when the host runs short.
  memory {
    dedicated = var.jumpbox.memory_mb
    floating  = 4096
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

  # The lifeline (docs/runbooks/set-up-the-box-lifeline.md, pick 220): a second NIC on the Proxmox
  # host's own bridge, so the box keeps a route to the Proxmox API when OPNsense is gone. It is the
  # second device, so the guest sees it as the second interface. Off unless var.lifeline is set.
  dynamic "network_device" {
    for_each = var.lifeline == null ? [] : [var.lifeline]
    content {
      bridge = network_device.value.bridge
      model  = "virtio"
    }
  }

  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${var.jumpbox.address}/24"
        gateway = cidrhost([for v in yamldecode(file(var.vlans_file)).lab_vlans : v.cidr if v.name == var.vnet][0], 1)
      }
    }

    # The lifeline's address, with no gateway: only the host's own subnet is reached over it, never
    # the internet, and the box's default route stays through the dev VLAN's gateway.
    dynamic "ip_config" {
      for_each = var.lifeline == null ? [] : [var.lifeline]
      content {
        ipv4 {
          address = "${ip_config.value.address}/${ip_config.value.prefix}"
        }
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
