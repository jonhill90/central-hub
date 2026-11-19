---
title: Rebuild the lab's host, network and firewall layer on a test copy in dev before prod
status: proposed
date: 2026-11-18
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Rebuild the lab's host, network and firewall layer on a test copy in dev before prod

## What and why

[Rebuild the home lab from bare metal](../runbooks/rebuild-home-lab-from-scratch.md) has never run end to end (its line 17). Its Kubernetes layer, steps 6 to 15, is code and proven on dev ([Rebuild one cluster's Kubernetes layer](../runbooks/rebuild-k8s-layer-with-one-command.md), Proven runs). The layer below it, the Proxmox host, the lab network and the firewall (steps 1 to 5), has never run as written. Much of it is still hand work:

- installing and locking down the host;
- staging the images;
- the OPNsense console step, which [Set up the lab network and firewall](../runbooks/set-up-lab-network-and-firewall.md) calls "this step has no code" (line 87);
- the API user, sent through the guest agent;
- the WAN safety check;
- the tailnet client in CT 900.

[D-0035](../decisions/0035-let-agents-tear-down-and-rebuild-the-lab-on-the-owners-github-approval.md) rule 3(a) lets a layer run on prod only after the same change passed that layer on dev. Dev today, pool `dev` and VMs 250 to 257, holds a copy of the Kubernetes layer and a throwaway OPNsense (VM 257). It has no copy of the host, its SDN, VM 100 or CT 900. So the host, network and firewall layer has nowhere to pass first.

This change adds that place: **a test copy**, one Proxmox VE VM in pool dev with nested virtualisation. It runs its own SDN, its own OPNsense and its own connector container, all built by the same code that builds the real ones. Proxmox names this use: nested virtualisation lets you "test some dangerous/tricky procedure involving hypervisors before actually doing it on the real thing" ([Proxmox VE wiki, Nested Virtualization](https://pve.proxmox.com/wiki/Nested_Virtualization)). Each hand step then becomes code on the copy first.

It serves the PRD's goal of a platform an agent can tear down and rebuild from this repository ([PRD](../PRD.md)).

## The copy

| Piece | Value | Why |
|---|---|---|
| VM | 256, pool `dev`, one NIC on VNet `dev`, never starts with the host | In dev's range (`hosts/terraform/home/bootstrap/agent-access.sh`, pool dev 250-257); 250-251 are dev's nodes and 257 is the OPNsense test VM |
| CPU | type `host`, 2 cores | `host` passes the hardware virtualisation flags through (Proxmox wiki, above); the OPNsense test VM already uses it (`hosts/terraform/home/opnsense-test/main.tf`) |
| Memory | 7168 MiB, no ballooning | 2048 for Proxmox VE itself, the documented minimum "for the OS and Proxmox VE services" ([System Requirements](https://pve.proxmox.com/wiki/System_Requirements)); 4096 for the nested OPNsense, because the copy runs the firewall run folder unchanged and it gives VM 100 4096 MiB with no ballooning (`hosts/terraform/home/firewall/main.tf`); 256 for the nested connector, as CT 900 has (`hosts/terraform/home/remote-access/main.tf`); 6400 in all, rounded up to whole GiB |
| Disk | 32 GB on `local-lvm`, thin | Room for the nested host, a 16 GB OPNsense disk as VM 257 has, and a container |
| Install | the Proxmox VE 9 ISO prepared with `proxmox-auto-install-assistant prepare-iso --fetch-from iso`, its answer file holding a root password hash, the box's SSH key and a static dev address | The prepared ISO's boot menu picks "Automated Installation" after 10 seconds, so no console is needed ([Automated Installation](https://pve.proxmox.com/wiki/Automated_Installation)); the agents' token has no `VM.Console` |
| Secrets | the nested root password, the nested `iac@pve` token and the nested OPNsense API key, made for the copy and removed with it | As the OPNsense test does; no prod secret is read |

Inside the copy, the code runs against the nested host, not the real one. The steps are:

- `playbooks/proxmox-host.yml` (vmbr1, mgmt);
- `hosts/terraform/home/bootstrap/iac-access.sh` over SSH as the nested root;
- the `network`, `firewall` and `remote-access` run folders, against the nested host's API;
- `playbooks/opnsense.yml`;
- the WAN safety check;
- `playbooks/proxmox-safety.yml`.

The nested vmbr1 has no ports, as on the real host, so the nested firewall's LAN DHCP stays inside the copy. Its WAN sits on a nested bridge with no ports, `vmbr9`, not on the nested vmbr0: the nested vmbr0 is VNet dev itself, and the nested firewall's own dev VLAN holds dev's range, so a live WAN there would put that range on two interfaces next to dev's real gateway. The WAN safety check runs before its WAN comes up, as it does on the real host.

## Memory

The copy needs 7168 MiB plus the 2048 MiB margin the OPNsense test uses: 9216 MiB. A dev rebuild needs 11008 MiB ([Dev node sizes](../runbooks/rebuild-k8s-layer-with-one-command.md#dev-node-sizes)). With dev down, the node's free memory read 7568 MiB and 11414 MiB at two times on 2026-11-18. So the copy runs only while dev is down and VM 257 does not exist; it would not have fitted at the lower reading, and it fits at the higher one with 2198 MiB to spare; and its wrapper refuses otherwise, as the OPNsense test's does. The dev rebuild refuses while VM 256 exists.

The first `prove` runs on 2026-11-18 met that lower range: 7431 MiB at 23:37 UTC, then 9245 MiB at plan and 7607 MiB at apply five seconds later, at 23:54 UTC. So when a guard is short and VM 300, the notebook's CI runner, is running, the guard stops VM 300 and nothing else, as the dev rebuild's preflight does, and destroy starts it again. VM 300 held 1913 MiB of the node's memory in the dev run of 2026-11-18 07:12 UTC ([Run the notebook runner on c1](../runbooks/run-the-notebook-runner-on-c1.md)). It stops only when the owner's short-node pick is set, because that pick is where the owner accepted that a short node may stop the runner.

## Out of scope

- **The real lab:** VM 100, CT 900, the real SDN and the host's own settings. The copy proves the code; a prod run of this layer is a separate step with the owner's go (D-0042 rule 6, D-0035 rule 3(b)).
- **SSH for agents on the real VM 100.** The copy's VM 100 gets it, so later steps can run commands there (installing a package from a file, for one). On the real firewall it is a new access right, which waits for the owner's go (D-0042 rule 6).
- **The tailnet:** the nested connector container is built and its client installed, but it never joins the tailnet, because that is a tailnet change.
- **The Kubernetes layer:** it is already proven on dev, and the copy has no memory for it.
- **Installing Proxmox on the real host:** D-0035 rule 1 leaves it to a person at the machine. The answer file this change writes is what that person would use.
- **Turning on nested virtualisation on the real host.** If the host's module does not have it on, enabling it reloads the module or reboots the host, which stops every guest. That stops this change and goes to the owner.

## Acceptance criteria

### Automated

- [ ] `tofu test` in `hosts/terraform/home/lab-test`: VM 256 in pool dev, CPU `host`, 7168 MiB, one NIC on VNet dev, never on boot.
- [ ] `bash .github/hosts-check/tests/test_rebuild_preflight.sh`: the dev preflight refuses while VM 256 exists.
- [ ] From inside VM 256: `grep -cE 'vmx|svm' /proc/cpuinfo` prints more than 0, and `pveversion` names Proxmox VE 9.
- [ ] On the nested host: a second `tofu plan` in `network`, `firewall` and `remote-access` shows no changes, and `opnsense.yml --check` reports `changed=0`.
- [ ] The WAN safety check's three moments on the nested WAN bridge pass: before link-up only a DHCP client runs, and the captures at link-up and over a reboot each count 0 server-type packets and more than 0 frames from the WAN.
- [ ] `proxmox-safety.yml` ends with its dead-man timer cancelled.
- [ ] `lab-test signin` passes the OPNsense sign-in prover's items 2 to 7, 9 and 10 on the copy's VM 100, with the pinned os-openid-connect package installed by `pkg add` and its server set by `opnsense-oidc-server.php` on the running firewall.
- [ ] The copy's VM 100 answers SSH as root by a key made on the box for that copy, and its `sshd -T` shows password sign-in off and listen addresses on LAN and loopback only, after first boot and again after `opnsense.yml`.
- [ ] Two clean runs in a row from the agent box, build to destroy, with no hand step, each with its log in the agent notebook's run records.

### Manual (what the owner checks)

- [ ] Nothing. The owner's go comes later, for the first prod run of this layer.

## Points to (read when)

- [Set up the lab network and firewall](../runbooks/set-up-lab-network-and-firewall.md): read when wiring each step against the nested host.
- [Set up a Proxmox VE host by hand](../runbooks/set-up-proxmox-host.md): read when turning its steps 0 to 6 into the answer file and a first-boot playbook.
- [Prove OPNsense sign-in through Keycloak on a throwaway dev VM](../runbooks/prove-opnsense-sign-in-on-dev.md): read for the pattern this copy follows (guards, token, uploads, destroy) and for an OPNsense first boot with no console.
- [D-0035](../decisions/0035-let-agents-tear-down-and-rebuild-the-lab-on-the-owners-github-approval.md): read for why dev comes first.

## Decision log

- 2026-11-18: one nested Proxmox VM, not a second set of lab objects on the real host. A second SDN zone or a second firewall on the real host would change the real host's network, and the agents' dev token cannot allocate SDN objects (`agent-access.sh`, role AgentDev has no `SDN.Allocate`). Agent pick.
- 2026-11-18: VM 256, the free ID nearest 257 in dev's range. Agent pick.
- 2026-11-18: 7168 MiB, not 6144. The first size counted the nested OPNsense at 3072 MiB, the OPNsense test's minimum, but the copy runs the firewall run folder as it is, and that gives VM 100 4096 MiB. Agent pick.
- 2026-11-18: the automated installer, not Debian 13 with the Proxmox packages added. The installer is what a person would use on the real host, so the answer file is proven too. Agent pick.
- 2026-11-18: the nested firewall's WAN on a nested bridge with no ports (`firewall`'s `wan_bridge`, default `vmbr0`), not the nested vmbr0, which is VNet dev; the capture asks for a server itself, since nothing else on that bridge would. Agent pick.
- 2026-11-18: SSH for root on the copy's VM 100 by a key the box makes for each copy and destroy removes, set by a PHP over the console like first boot, LAN only, password sign-in off. The prover and the package install need a shell on the firewall, and the API has none. Agent pick.
- 2026-11-18: the sign-in proof as a step of the copy, `lab-test signin`, after `opnsense`, and not only on VM 257. The copy runs the nano 26.1.6 image and the config the lab firewall runs, and the package and settings go on the way they can go on a running firewall. Its Keycloak runs on the box on loopback only, and VM 100 reaches it through a reverse forward on its SSH, so neither the copy nor the box's filter changes. Agent pick.
- 2026-11-19: a short guard stops VM 300, the CI runner, and destroy starts it again, as the dev rebuild does, and only with the owner's short-node pick set. The copy's two readings of 2026-11-18 23:54 UTC differed by 1638 MiB in five seconds with dev down. Agent pick.
