# Offline tests for home/k8s: plans against a mocked provider, so no Proxmox host or token is
# needed (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {
  # The provider checks that a disk's import_from is a Proxmox file ID, so the mocked download
  # gets one instead of a random string.
  mock_resource "proxmox_download_file" {
    defaults = {
      id = "local:import/almalinux-10.2-20261012.0-genericcloud.qcow2"
    }
  }
}

variables {
  proxmox_node_name   = "examplehv01"
  vlans_file          = "../../../ansible/inventories/home/group_vars/all/vlans.yml"
  node_ssh_public_key = "ssh-ed25519 AAAA...example"
  nodes = {
    palcpdemo01 = { vm_id = 200, role = "control-plane", cores = 2, memory_mb = 4096, disk_gb = 40, address = "10.1.10.11" }
    palwkdemo01 = { vm_id = 201, role = "worker", cores = 2, memory_mb = 4096, disk_gb = 40, address = "10.1.10.21" }
  }
}

# Spec home-lab-and-c1, decision log 2026-10-26: c1 nodes sit on VNet prod, VLAN 10.
run "nodes_on_prod_with_gateway_dot_one" {
  command = plan

  assert {
    condition     = alltrue([for k, n in proxmox_virtual_environment_vm.node : n.network_device[0].bridge == "prod"])
    error_message = "Every c1 node must sit on VNet prod."
  }

  assert {
    condition     = alltrue([for k, n in proxmox_virtual_environment_vm.node : n.initialization[0].ip_config[0].ipv4[0].gateway == "10.1.10.1"])
    error_message = "A node's gateway must be prod's .1 address (OPNsense), read from the shared VLAN file."
  }

  assert {
    condition     = alltrue([for k, n in proxmox_virtual_environment_vm.node : n.initialization[0].dns[0].servers == tolist(["10.1.10.1"])])
    error_message = "A node's DNS server must be prod's .1 address."
  }
}

# Spec home-lab-and-c1, decision log 2026-10-26: one pool per workload, named by job.
run "everything_in_pool_k8s" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_vm.template[0].pool_id == "k8s" && alltrue([for k, n in proxmox_virtual_environment_vm.node : n.pool_id == "k8s"])
    error_message = "The template and every node must be in pool k8s."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["palwkdemo01"].tags == tolist(["almalinux", "prod", "selfhosted", "worker"])
    error_message = "A node's tags must end with its role."
  }
}

# The agents' dev rebuild may add guests only to pool dev, so the pool is a variable; c1 keeps k8s.
run "pool_is_set_by_variable" {
  command = plan

  variables {
    pool_id = "dev"
  }

  assert {
    condition     = proxmox_virtual_environment_vm.template[0].pool_id == "dev" && alltrue([for k, n in proxmox_virtual_environment_vm.node : n.pool_id == "dev"])
    error_message = "pool_id must set the pool of the template and every node."
  }
}

# Spec home-lab-and-c1, decision log 2026-10-26: a pinned image, not "latest" (STD-0003).
run "image_pinned_with_checksum" {
  command = plan

  assert {
    condition     = !strcontains(var.almalinux_image_url, "latest") && length(var.almalinux_image_sha256) == 64
    error_message = "The node image must be one pinned build with its SHA-256."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.template[0].template && !proxmox_virtual_environment_vm.template[0].started
    error_message = "The template must be a template and never started."
  }
}

# A different VNet moves the gateway with it: the gateway comes from the VLAN file, not the code.
run "gateway_follows_vnet" {
  command = plan

  variables {
    node_vnet = "dev"
    nodes = {
      palwkdemo01 = { vm_id = 201, role = "worker", cores = 2, memory_mb = 4096, disk_gb = 40, address = "10.1.30.21" }
    }
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["palwkdemo01"].initialization[0].ip_config[0].ipv4[0].gateway == "10.1.30.1"
    error_message = "On VNet dev the gateway must be dev's .1 address."
  }
}

# BUILD-PATH S17: a node with data_disk_gb gets an empty scsi1 for Kubernetes volumes; one
# without it keeps only its OS disk.
run "data_disk_only_where_asked" {
  command = plan

  variables {
    nodes = {
      palcpdemo01 = { vm_id = 200, role = "control-plane", cores = 2, memory_mb = 4096, disk_gb = 40, address = "10.1.10.11" }
      palwkdemo01 = { vm_id = 201, role = "worker", cores = 2, memory_mb = 4096, disk_gb = 40, data_disk_gb = 200, address = "10.1.10.21" }
    }
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.node["palcpdemo01"].disk) == 1
    error_message = "A node without data_disk_gb must have only its OS disk."
  }

  assert {
    condition     = anytrue([for d in proxmox_virtual_environment_vm.node["palwkdemo01"].disk : d.interface == "scsi1" && d.size == 200 && d.datastore_id == "local-lvm"])
    error_message = "A node with data_disk_gb must get a scsi1 data disk of that size on local-lvm."
  }
}

# A rehearsal cluster beside c1: its own state clones the template c1's state owns, makes no
# template or image of its own, and tags its nodes with its VNet.
run "second_cluster_clones_existing_template" {
  command = plan

  variables {
    create_template = false
    node_vnet       = "dev"
    nodes = {
      dalcprehearse01 = { vm_id = 250, role = "control-plane", cores = 2, memory_mb = 4096, disk_gb = 40, address = "10.1.30.11" }
    }
  }

  assert {
    condition     = length(proxmox_virtual_environment_vm.template) == 0 && length(proxmox_download_file.almalinux10) == 0
    error_message = "With create_template = false the state must make no template and download no image."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["dalcprehearse01"].clone[0].vm_id == 9000
    error_message = "The nodes must clone template_vm_id."
  }

  assert {
    condition     = proxmox_virtual_environment_vm.node["dalcprehearse01"].tags == tolist(["almalinux", "dev", "selfhosted", "control-plane"])
    error_message = "A node's tags must name its VNet."
  }
}
