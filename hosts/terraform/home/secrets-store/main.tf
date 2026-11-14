# The lab's secrets store, OpenBao, on its own VM in each env (proposed D-0038, option 1). One
# AlmaLinux 10 VM cloned from template 9001; what runs inside it is the openbao role
# (playbooks/openbao.yml). Dev first: VM 550, on VNet dev in pool dev, where the agents' token
# already holds its rights; the name is a STD-0001 hostname in the private inventory; prod (VM 500) follows D-0035 rule 3. The VM IDs 500-599
# are the next free hundred under STD-0001 (agent pick, D-0038 rule 2).
# Applied from the agent box by the secrets-store wrapper (docs/runbooks/set-up-the-secrets-store.md).
# Exit: tofu destroy with this folder's state, after a final Raft snapshot (the runbook's "Remove it").

resource "proxmox_virtual_environment_vm" "store" {
  node_name = var.proxmox_node_name
  vm_id     = var.store.vm_id
  name      = var.store.name
  pool_id   = var.pool_id
  tags      = ["almalinux", var.vnet, "openbao"]

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
    cores = var.store.cores
  }

  memory {
    dedicated = var.store.memory_mb
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
    size         = var.store.disk_gb
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
        address = "${var.store.address}/24"
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
