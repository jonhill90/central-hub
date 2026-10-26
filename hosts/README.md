# hosts

Code for every machine below Kubernetes ([D-0011](../docs/decisions/0011-keep-machine-code-in-hosts.md)). Each tool has its own subfolder:

| Folder | What it does |
|---|---|
| [terraform/](terraform/) | Creates Proxmox objects: the lab SDN, the OPNsense VM and the connector container. |
| [ansible/](ansible/) | Configures the Proxmox host's network and the OPNsense firewall's settings. |

Status: first draft. Nothing here has been applied to the lab yet.

## Order for the home lab

1. Ansible, `playbooks/proxmox-host.yml --tags vmbr1`: gives vmbr1 a fixed MAC, so the SDN VLAN devices on it can come up.
2. Terraform, one run folder at a time: `hosts/terraform/home/network/` (SDN zone, VNets, subnets), then `home/firewall/` (VM 100) and `home/remote-access/` (CT 900). Each has its own state and `backend.tf`.
3. Ansible, `playbooks/proxmox-host.yml --tags mgmt`: adds the host's address on VNet mgmt, which needs the SDN from step 2.
4. At the OPNsense console, by hand: root password, the mgmt VLAN as LAN with its address, and an API key. Ansible reaches the firewall through that address, so it has to exist first.
5. Ansible, `playbooks/opnsense.yml`: the other VLANs, interface assignment, DHCP, rules and the DNS override.

## Private values

This repository is public. Host names, domain names, tailnet names, MAC addresses, the home LAN range and single machine addresses are never written here. The code takes them as variables with no default, filled from the secret store at apply time. Which secret store is still open. Ranges from the IP address plan, such as `10.1.0.0/16` and its VLAN /24s, are written here.
