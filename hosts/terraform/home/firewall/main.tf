# VM 100: the OPNsense firewall for the lab VLANs.
# net0 is the trunk on vmbr1 (all lab VLANs, tagged inside OPNsense) and must stay first.
# net1 is WAN on vmbr0; it stays link-down on a fresh build until the WAN safety check passes.
# Needs home/network applied first (the VLANs ride on vmbr1).
# The console steps inside the VM (password, mgmt VLAN, LAN address, API key) are not done here.

resource "proxmox_virtual_environment_vm" "opnsense" {
  node_name = var.proxmox_node_name
  vm_id     = 100
  pool_id   = "firewall" # the pool itself is made by bootstrap/iac-access.sh
  name      = var.firewall_vm_name
  tags      = ["opnsense", "prod", "selfhosted"]

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"
  boot_order    = ["scsi0"]

  on_boot = true
  started = true

  startup {
    order = 1
  }

  operating_system {
    type = "other"
  }

  cpu {
    type  = "host"
    cores = 2
  }

  memory {
    dedicated = 4096
    floating  = 0
  }

  agent {
    enabled = true
  }

  serial_device {
    device = "socket"
  }

  vga {
    type = "serial0"
  }

  disk {
    interface    = "scsi0"
    datastore_id = "local-lvm"
    import_from  = var.opnsense_image_file_id
    size         = 16
    iothread     = true
  }

  network_device {
    bridge      = var.trunk_bridge
    model       = "virtio"
    mac_address = var.opnsense_lan_mac
  }

  network_device {
    bridge       = "vmbr0"
    model        = "virtio"
    mac_address  = var.opnsense_wan_mac
    disconnected = !var.opnsense_wan_connected
  }

  lifecycle {
    # The image is read only when the disk is first created.
    ignore_changes = [disk[0].import_from]
  }
}
