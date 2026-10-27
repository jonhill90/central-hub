# Offline tests for home/remote-access: a plan against a mocked provider, so no Proxmox host or
# token is needed (STD-0005). Values are made up, as in home.tfvars.example.

mock_provider "proxmox" {}

variables {
  proxmox_node_name      = "examplehv01"
  connector_eth0_mac     = "02:00:00:00:00:03"
  connector_mgmt_address = "10.1.50.90/24"
  connector_hostname     = "pdenwdemo01"
  # Needed to create the container; the running CT 900 was imported, so home.tfvars leaves it out.
  connector_template_file_id = "local:vztmpl/debian-13-standard_13.1-2_amd64.tar.zst"
}

# eth0 on vmbr0 by DHCP; eth1 on VNet mgmt with a fixed address and no gateway.
run "connector_networks" {
  command = plan

  assert {
    condition     = proxmox_virtual_environment_container.ts_connector.network_interface[0].bridge == "vmbr0" && proxmox_virtual_environment_container.ts_connector.initialization[0].ip_config[0].ipv4[0].address == "dhcp"
    error_message = "eth0 must be on vmbr0 and take its address by DHCP."
  }

  assert {
    condition     = proxmox_virtual_environment_container.ts_connector.network_interface[1].bridge == "mgmt" && proxmox_virtual_environment_container.ts_connector.initialization[0].ip_config[1].ipv4[0].gateway == null
    error_message = "eth1 must be on VNet mgmt with no gateway."
  }

  assert {
    condition     = proxmox_virtual_environment_container.ts_connector.unprivileged && proxmox_virtual_environment_container.ts_connector.vm_id == 900
    error_message = "The connector must be unprivileged CT 900."
  }
}
