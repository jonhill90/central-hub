# A desktop in the lab for the owner (his words, 2026-11-13 05:04 UTC: to be able to VNC or RDP in and
# log in to apps by hand). One AlmaLinux 10 VM on VNet dev, cloned from template 9001, running Xfce and
# xrdp (the desktop role). It holds no lab keys and no agent credentials: what the owner types into it
# never sits beside the agents' keys. The VM and its ID are agent picks, hosts/AGENT-PICKS.md.
# The agents' token may create it on its /vms/<id> rights alone, with no pool (it has no Pool.Allocate).
# Applied from the agent box by the desktop wrapper (docs/runbooks/set-up-the-desktop.md).
# Exit: tofu destroy with this folder's state.

resource "proxmox_virtual_environment_vm" "desktop" {
  node_name = var.proxmox_node_name
  vm_id     = var.desktop.vm_id
  name      = var.desktop.name
  pool_id   = var.pool_id
  tags      = ["almalinux", var.vnet, "desktop"]

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
    cores = var.desktop.cores
  }

  memory {
    dedicated = var.desktop.memory_mb
    floating  = 0
  }

  agent {
    enabled = true
  }

  serial_device {
    device = "socket"
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    size         = var.desktop.disk_gb
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
        address = "${var.desktop.address}/24"
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
