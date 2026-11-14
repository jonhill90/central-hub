---
title: Give the agent box a lifeline to Proxmox and keep OPNsense's configuration
status: draft
kind: manual
trigger: once, before any agent teardown that includes OPNsense (D-0035); again if the host's bridge or subnet changes
runner: the owner's go, then an agent session on the agent box and one run of the box's role from the Mac
outcome: VM 258 has a second NIC on the Proxmox host's own subnet, so the box keeps its route to the Proxmox API when OPNsense is gone, and the box holds a daily copy of OPNsense's configuration
needs: the filled-in private tfvars for hosts/terraform/home/jumpbox; the owner's typed go (this changes the box's network); the Proxmox host firewall allowing the box's new address to 8006
private-values: [lifeline-bridge, lifeline-address, opnsense-host, lifeline-interface]
files: [hosts/terraform/home/jumpbox/, hosts/ansible/roles/agent_box/tasks/lifeline.yml, hosts/ansible/roles/agent_box/files/opnsense-backup.sh]
last-tested: not yet run
superseded-by:
---

# Give the agent box a lifeline to Proxmox and keep OPNsense's configuration

**Status:** draft. Written 2026-11-13 from the code in this change (offline tests only). Not run, and the apply is the owner's call: it changes the network of VM 258, the machine the agents work from.

## Why

The box reaches the Proxmox API through OPNsense (the box sits on VNet dev; the Proxmox host is on the home LAN). An agent that destroys OPNsense in a rebuild loses that route and cannot rebuild it (AGENT-REDEPLOY-PLAN, hard problem 1). This gives the box a path that does not depend on anything it rebuilds, and keeps a copy of OPNsense's configuration so a rebuilt firewall can be put back.

## What is built (pick 220)

| Piece | Where |
|---|---|
| Second NIC | `hosts/terraform/home/jumpbox`, variable `lifeline` (`bridge`, `address`, `prefix`), default null: a second `network_device` on the Proxmox host's own bridge and a second `ip_config` with an address and **no gateway**, so only the host's subnet is reached over it and the box's default route stays through the dev VLAN |
| Closed both ways | role `agent_box`, variables `agent_box_lifeline_interface` (the NIC's name inside the VM) and `agent_box_lifeline_allow` (entries of `address` and `ports`, normally the Proxmox host and 8006). Inbound: the interface and its NetworkManager connection are in firewalld's `drop` zone, so nothing on the home LAN can start a connection to the box. Outbound: a firewalld policy from the box itself to that zone accepts only the listed addresses and ports and rejects the rest, so the connected route does not let a session reach other home LAN devices |
| Configuration copy | role `agent_box`, variable `agent_box_opnsense_backup` (`host`, `keep`): `opnsense-backup.sh` runs daily as the keys user, fetches the configuration from OPNsense's API with the key in `/etc/agent-keys/prod/opnsense-api.txt` (sent to curl on stdin), keeps the newest copies in `/var/lib/agent-box/opnsense-backup` (folder 0700, files 0600) and refuses anything that is not an OPNsense configuration |

With the second NIC on the host's subnet, the connected route to the Proxmox API is more specific than the default one, so the box reaches the API over the lifeline all the time, not only when OPNsense is down.

## What this does not do, and what is the owner's

- **It does not reach the tailnet or the internet without OPNsense, and that is the owner's pick.** The owner chose "Proxmox host only" on a card on 2026-11-14 at 02:23 UTC: the lifeline gets no gateway and reaches only the Proxmox host's own subnet, and by the firewalld outbound policy only the addresses and ports in `agent_box_lifeline_allow`. With OPNsense gone the box can still reach the Proxmox API (to rebuild it) but has no internet until OPNsense is back. A gateway through the home router would give it internet, and would also expose the box to the home LAN's router path; the owner did not pick that, so do not add one.
- **The Proxmox host's own firewall.** Its rule for port 8006 accepts the datacenter IPSet `management`, and Proxmox adds the host's own LAN to that set by itself (a comment in the `proxmox_firewall` role's defaults, not yet proven here). The lifeline NIC sits on that LAN, so 8006 from it may already pass with no change. Step 3 proves it; only if it fails does the box's lifeline address need its own rule, which is a firewall change and so the owner's words.
- **The copy is on the box.** `opnsense-backup` keeps its copies on VM 258, where a destroyed OPNsense cannot touch them, but the box is not off-box storage. The owner picked the Azure backup account for the off-box copy, with its own container, credential and password: [Copy the OPNsense configuration backups off the agent box](copy-opnsense-backup-off-box.md). Restoring is OPNsense's own: System, Configuration, Backups, Restore, or the API's `core/backup` calls.

## Steps (after the owner's go)

1. Fill in `lifeline` in the git-ignored tfvars: the host's own bridge (`vmbr0` or as `pvesh get /nodes/<node>/network` shows), a free address on its subnet, the prefix. Never in the repository.
   expect: `tofu plan` (through the box's `dev-vms`-style wrapper for this folder, or from the Mac) shows an update in place of VM 258: one more `network_device` and `ip_config`, nothing destroyed. If it shows a replace, stop.

2. Apply, then give the new interface its zone straight away. Between the apply of step 1 and this step the new NIC is in the default zone with no outbound policy, so do this right after the apply, not later. Set `agent_box_lifeline_interface`, `agent_box_lifeline_allow` and `agent_box_opnsense_backup` in the private inventory and run the box's role from the Mac.
   expect: `failed=0`; `firewall-cmd --get-zone-of-interface=<nic>` prints `drop`; `nmcli -g connection.zone connection show <connection>` prints `drop` (so it survives a reconnect; after a reboot of the box the first command must still print `drop`); `systemctl list-timers opnsense-backup.timer` lists the timer; from the box, `curl -sk --max-time 5 https://<another home LAN address>:443/` fails at once (rejected), while the allowed address and port still connect.

3. Prove the Proxmox API answers over the lifeline, before any host firewall change. Take the route first: `ip route get <host>` from the box must name the lifeline interface (the connected route is more specific than the default). Then, as the keys user's wrapper allows or from a session on the box, `curl -sk --max-time 5 -o /dev/null -w '%{http_code}' https://<host>:8006/`.
   why: Proxmox puts the host's own LAN into the `management` IPSet that the 8006 rule accepts, so no new rule may be needed (inferred from the role's comment, untested).
   expect: `ip route get` shows the lifeline interface and the curl prints `200` or `401`. If it times out, the host firewall is dropping the lifeline address: stop and ask the owner. With their words, add the box's lifeline address to `proxmox_firewall_extra_rules` in the private inventory (an ACCEPT for tcp 8006 from that address) and run the `proxmox_firewall` role, which arms its dead-man timer first; then run this step again.

4. Run one backup by hand as the keys user and check it.
   expect: `opnsense-backup: kept config-<stamp>.xml (1 copies)`; the file starts with `<?xml` and contains `<opnsense>`.

## If it fails

- `opnsense-backup: what came back is not an OPNsense configuration`: the API key lacks the backup privilege, or the host answered with a login page. The older copies are kept.
- `curl: (60)` certificate error: the box does not trust the lab CA that signs OPNsense's certificate (`agent_box_ca_files`).
- The plan shows a replace of VM 258: stop; a changed NIC order or a template change can do that. Nothing here should destroy the box.

## Exit

Set `lifeline` to null and `agent_box_lifeline_interface` to empty, apply, and remove the timer by emptying `agent_box_opnsense_backup`.
