# hosts/ansible

Ansible code that configures the Proxmox host's network and the OPNsense firewall's settings.

## What it builds

| Playbook | Role | What it sets |
|---|---|---|
| `playbooks/proxmox-host.yml` | `proxmox_network` | Tag `vmbr1`: bridge vmbr1 with no ports, VLAN-aware 2-4094, and a fixed MAC. A bridge with no ports otherwise gets an all-zero MAC, and then the SDN's VLAN devices on it can't come up. Tag `mgmt`: the host's address on VNet mgmt, with no gateway. The host's home LAN address on vmbr0 is checked after every reload and never changed. |
| `playbooks/opnsense.yml` | `opnsense_lab` | VLANs 10, 20 and 30 on the trunk port, and their interface slots with the `.1/24` gateway address. DHCP pools `.100` to `.199` on VLANs 10 and 30 only, ending before the `.224/27` load-balancer reserve. Four rules per lab VLAN: block the home LAN, allow ping and DNS to the firewall, allow everything that isn't RFC 1918. An Unbound host override `opnsense.<zone>` pointing at the mgmt gateway. On WAN: home LAN to the mgmt gateway on tcp 443, tcp/udp 53 and ping, and private sources no longer blocked. |

The OPNsense role uses the `oxlorg.opnsense` collection, which calls the OPNsense API from the controller. The mgmt VLAN and its LAN slot are made at the console before the API can be reached, so the role leaves them alone.

## Private values

`inventories/home/hosts.example.yml` is the inventory template for the home place (one `inventories/<place>/` per place, matching `terraform/<place>/`). Every blank in it is a private value, filled from the secret store at run time. Save the filled-in copy as `inventories/home/hosts.yml` (git-ignored) and pass `-i inventories/home/`, so Ansible also loads `group_vars/all/vlans.yml`, the one shared VLAN file that `terraform/home/network` reads too. The roles stop with an error if a private value is missing, because the roles give these values no default.

## Run it

```sh
pip install -r requirements.txt
ansible-galaxy collection install -r requirements.yml -p ./collections
ansible-playbook -i <filled-in inventory> playbooks/proxmox-host.yml --tags vmbr1 --check --diff
ansible-playbook -i <filled-in inventory> playbooks/opnsense.yml --check --diff
```

Run each playbook with `--check --diff` first: against the running lab it should report no changes. The order with Terraform is in [../README.md](../README.md).

Checked so far: `ansible-playbook --syntax-check` passes for both playbooks, and `ansible-lint` passes the production profile. Its only warnings say that the API connection arguments are missing, because they are set once in the playbook, not in each task. It has never run against the lab.

## Still open

- No release of `oxlorg.opnsense` for OPNsense 26.7 has been seen yet. The pinned 26.1.11 is tested on 26.1.
- The import of the running lab's objects is untested. The VLANs made at the console are named `vtnet0_vlan<tag>`, while the collection names new ones `vlan0.<tag>`. Its DHCP ranges, VLANs and rules are matched by description, and the console-made ones may not carry these descriptions.
- The vmbr1 MAC field is unchecked: whether `hwaddress` in the vmbr1 stanza, written through `interfaces_file`, keeps the MAC fixed across `ifreload` and Proxmox network edits.
- The collection has no module for interface assignment. The role calls the `interfaces/assignment` API through the collection's `raw` module instead. That API is in the current OPNsense API docs, but its presence in 26.7 and the shape of its replies are unverified. The WAN `blockpriv` change uses the same API.
- The `dnsmasq_general` module sets every general dnsmasq setting at once; the ones the role doesn't name go to the collection's defaults.
- Whether OPNsense's default "allow LAN to any" rules are rules this API manages on 26.7 is unchecked.
- Not covered yet: the GUI's alternate hostname, which its DNS-rebind check needs for `opnsense.<zone>`, and everything inside the connector container.
