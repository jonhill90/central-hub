# The lab test copy: one Proxmox VE 9 VM on VNet dev that holds its own SDN, its own OPNsense and its own
# connector container, so the host, network and firewall layer can pass on dev before prod (D-0035 rule 3(a);
# docs/specs/2026-11-lab-test-copy.md). Built only while dev is down and VM 257 does not exist.
# Its install needs no console, which the agents' token lacks (no VM.Console): it boots the Proxmox VE 9
# installer ISO the wrapper prepared with `proxmox-auto-install-assistant prepare-iso --fetch-from iso`, whose
# boot menu picks "Automated Installation" by itself after 10 seconds (https://pve.proxmox.com/wiki/Automated_Installation).
# The empty disk comes first in the boot order, so the first boot falls through to the installer and every
# later boot starts the installed system.
# CPU type host passes the hardware virtualisation flags through, so the copy's own guests run with KVM, as
# long as the host's kvm module has `nested` on (https://pve.proxmox.com/wiki/Nested_Virtualization). Not read
# here; the wrapper checks for vmx or svm inside the copy.
# Exit: `lab-test destroy`, which destroys the VM and leaves the installer ISO on local for the owner (the
# agents' token cannot delete files there).

# The prepared installer ISO, uploaded through the API (Datastore.AllocateTemplate on local). The agents'
# token cannot delete files on local (no Datastore.Allocate), so each ISO is named by its hash: a new ISO is
# a new file and never needs a delete.
resource "proxmox_virtual_environment_file" "installer" {
  node_name    = var.proxmox_node_name
  datastore_id = "local"
  content_type = "iso"

  source_file {
    path      = var.installer_iso_path
    file_name = "lab-test-${var.vm.vm_id}-pve-auto-${substr(var.installer_iso_sha256, 0, 12)}.iso"
    checksum  = var.installer_iso_sha256
  }
}

resource "proxmox_virtual_environment_vm" "host" {
  node_name = var.proxmox_node_name
  vm_id     = var.vm.vm_id
  name      = var.vm.name
  pool_id   = var.pool_id
  # No tags: a create's tags are checked on /vms/<id> before the VM is in pool dev, where the agents' token
  # has no right (as for VM 257, hosts/terraform/home/opnsense-test/main.tf).

  on_boot = false
  started = true

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0", "ide2"]

  operating_system {
    type = "l26"
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
    file_format  = "raw"
    size         = var.vm.disk_gb
    iothread     = true
    discard      = "on"
  }

  cdrom {
    interface = "ide2"
    file_id   = proxmox_virtual_environment_file.installer.id
  }

  # One NIC on dev. The copy's own vmbr0 sits on it; its vmbr1 has no ports, as on the real host, so the
  # nested firewall's LAN side never reaches VNet dev.
  network_device {
    bridge = var.vnet
    model  = "virtio"
  }
}
