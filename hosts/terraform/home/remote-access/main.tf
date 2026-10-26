# CT 900: the tailnet connector container, as an object only.
# Needs home/network applied first (eth1 joins VNet mgmt).
# eth0 sits on vmbr0 and takes its address by DHCP; eth1 sits on VNet mgmt with a fixed address
# and no gateway. What runs inside it (the tailnet client, sysctl, routes) is not done here.

resource "proxmox_virtual_environment_container" "ts_connector" {
  node_name    = var.proxmox_node_name
  vm_id        = 900
  tags         = ["debian", "prod", "selfhosted"]
  unprivileged = true

  start_on_boot = true
  started       = true

  operating_system {
    template_file_id = var.connector_template_file_id
    type             = "debian"
  }

  console {
    enabled   = true
    tty_count = 2
    type      = "tty"
  }

  cpu {
    cores = 1
  }

  memory {
    dedicated = 256
    swap      = var.connector_swap_mb
  }

  disk {
    datastore_id = "local-lvm"
    size         = 2
  }

  features {
    keyctl  = true
    nesting = true
  }

  device_passthrough {
    path = "/dev/net/tun"
  }

  network_interface {
    name        = "eth0"
    bridge      = "vmbr0"
    mac_address = var.connector_eth0_mac
  }

  network_interface {
    name   = "eth1"
    bridge = var.mgmt_vnet
  }

  initialization {
    hostname = var.connector_hostname

    ip_config {
      ipv4 {
        address = "dhcp"
      }
    }

    ip_config {
      ipv4 {
        address = var.connector_mgmt_address
      }
    }
  }

  lifecycle {
    # The template is read only when the container is first created.
    ignore_changes = [operating_system[0].template_file_id]
  }
}
