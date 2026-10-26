# Kubernetes cluster c1, its node VMs (BUILD-PATH S06). One AlmaLinux 10 cloud-image template,
# and the nodes cloned from it onto VNet prod (VLAN 10, STD-0002). Needs home/network applied
# first. What runs inside the nodes (kubeadm, containerd, Cilium) is Ansible's job, not this.

# The AlmaLinux 10 GenericCloud image, stored as an "import" file on the host's local storage.
resource "proxmox_download_file" "almalinux10" {
  node_name    = var.proxmox_node_name
  datastore_id = "local"
  content_type = "import"
  url          = var.almalinux_image_url
  file_name    = "almalinux-10-genericcloud.qcow2"
  overwrite    = false
}

# The template every node is cloned from. Never started.
resource "proxmox_virtual_environment_vm" "template" {
  node_name = var.proxmox_node_name
  vm_id     = 9000
  name      = "almalinux10-template"
  pool_id   = "k8s"
  tags      = ["almalinux", "template"]
  template  = true
  started   = false

  machine       = "q35"
  bios          = "seabios"
  scsi_hardware = "virtio-scsi-single"

  operating_system {
    type = "l26"
  }

  cpu {
    type  = "host"
    cores = 2
  }

  memory {
    dedicated = 2048
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
    import_from  = proxmox_download_file.almalinux10.id
    size         = 20
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = var.node_vnet
    model  = "virtio"
  }

  initialization {
    datastore_id = "local-lvm"
  }
}

# The nodes. Keys of var.nodes are the hostnames (STD-0001), set only in the git-ignored tfvars.
resource "proxmox_virtual_environment_vm" "node" {
  for_each = var.nodes

  node_name = var.proxmox_node_name
  vm_id     = each.value.vm_id
  name      = each.key
  pool_id   = "k8s"
  tags      = ["almalinux", "prod", "selfhosted", each.value.role]

  on_boot = true
  started = true

  clone {
    vm_id = proxmox_virtual_environment_vm.template.vm_id
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
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory_mb
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
    size         = each.value.disk_gb
    iothread     = true
    discard      = "on"
  }

  network_device {
    bridge = var.node_vnet
    model  = "virtio"
  }

  # Fixed address on VNet prod, gateway .1 (OPNsense), which is also the DNS server.
  # The VNet's range comes from the one shared VLAN file, so it is written once.
  initialization {
    datastore_id = "local-lvm"

    ip_config {
      ipv4 {
        address = "${each.value.address}/24"
        gateway = cidrhost([for v in yamldecode(file(var.vlans_file)).lab_vlans : v.cidr if v.name == var.node_vnet][0], 1)
      }
    }

    dns {
      servers = [cidrhost([for v in yamldecode(file(var.vlans_file)).lab_vlans : v.cidr if v.name == var.node_vnet][0], 1)]
    }

    user_account {
      username = var.node_admin_user
      keys     = [var.node_ssh_public_key]
    }
  }
}
