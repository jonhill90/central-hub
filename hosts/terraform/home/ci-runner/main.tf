# The notebook's self-hosted CI runner (the owner's go of 2026-11-10 20:05 UTC to move the notebook's
# CI off GitHub-hosted minutes; the VM is an agent pick, hosts/AGENT-PICKS.md). One small AlmaLinux 10
# VM on VNet dev, cloned from template 9000. It holds no lab keys and can't reach the Proxmox API:
# the host firewall lets only the agent box reach 8006. What runs inside it is the ci_runner role.
# Applied from the agent box by the ci-runner wrapper (docs/runbooks/set-up-the-ci-runner.md).
# Exit: tofu destroy with this folder's state, after removing the runner from the repository.

resource "proxmox_virtual_environment_vm" "runner" {
  node_name = var.proxmox_node_name
  vm_id     = var.runner.vm_id
  name      = var.runner.name
  pool_id   = var.pool_id
  tags      = ["almalinux", var.vnet, "ci"]

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
    cores = var.runner.cores
  }

  memory {
    dedicated = var.runner.memory_mb
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
    size         = var.runner.disk_gb
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
        address = "${var.runner.address}/24"
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
