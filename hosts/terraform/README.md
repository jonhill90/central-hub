# hosts/terraform

Run folders laid out as `<place>/<workload>/` (Jon, 2026-10-25 20:57 UTC: "1 seems right", layout A from RB-0083). Each run folder is one root module with its own state and its own `backend.tf`.

| Run folder | What it makes | Needs first |
|---|---|---|
| [home/network/](home/network/) | SDN zone `lab` on vmbr1, VNets `prod` (10), `qa` (20), `dev` (30), `mgmt` (50), one `10.1.<tag>.0/24` subnet each, and the SDN applier | vmbr1 with a fixed MAC (Ansible, `proxmox-host.yml --tags vmbr1`) |
| [home/firewall/](home/firewall/) | VM 100, the OPNsense firewall (net0 trunk on vmbr1, net1 WAN on vmbr0) | home/network |
| [home/remote-access/](home/remote-access/) | CT 900, the tailnet connector (eth0 on vmbr0, eth1 on VNet mgmt) | home/network |

Every run folder has the same files: `main.tf` (the resources), `variables.tf`, `outputs.tf`, `providers.tf`, `versions.tf`, `backend.tf`, `imports.tf` (adopts the running lab's objects) and its own `.terraform.lock.hcl`.

Run folders don't read each other's state. A value one folder needs from another, such as the VNet name `mgmt`, is an input variable with the same value as the producer's output (`home/network` output `vnet_ids`). That choice, the place name `home` and the rest are listed in [../AGENT-PICKS.md](../AGENT-PICKS.md) for Jon's review.

## Run one folder

```sh
cd home/network
tofu init -backend-config="path=<folder outside the repo>/home-network.tfstate"
tofu plan -var vlans_file=../../../ansible/inventories/home/group_vars/all/vlans.yml
```

`home/network` reads its VLANs from the one shared VLAN file, `ansible/inventories/<place>/group_vars/all/vlans.yml`, which Ansible also loads, so the VLAN list is written once. `var.vlans_file` has no default. Real `*.tfvars` files are git-ignored.

`home/firewall` and `home/remote-access` have no default for the machine's name (`firewall_vm_name`, `connector_hostname`). Their `home.tfvars.example` files hold made-up STD-0001-shaped names; the real names go only in the git-ignored `home.tfvars`.

Private values (node name, MACs, the connector's mgmt address) come from the secret store as `TF_VAR_<name>`, and the provider reads `PROXMOX_VE_ENDPOINT` and `PROXMOX_VE_API_TOKEN`. Nothing here has been planned or applied against the lab.
