---
id: D-0040
title: Keep OPNsense's community edition as the lab's router, firewall and DNS for now, using no Business Edition feature
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
revisit-when: a research batch compares FOSS routers and firewalls for the lab feature by feature; a feature the lab needs turns out to be in the Business Edition only; OPNsense or Deciso changes the licence or moves a community feature to the paid edition; or the lab moves to a hardware firewall
---

# Keep OPNsense's community edition as the lab's router, firewall and DNS for now, using no Business Edition feature

## Context and Problem Statement

The lab's router, firewall, VLAN gateway, DHCP server and lab DNS is an OPNsense virtual machine on the Proxmox host. It was set up by hand before the lab was in code ([home-lab-and-c1 spec](../specs/2026-10-home-lab-and-c1.md)) and was later brought into code: role `opnsense_lab` and the shared VLAN file in `hosts/ansible/`, and `hosts/terraform/home/firewall/`. No decision record chose it. Records D-0011, D-0017, D-0021, D-0028 and D-0036 and 22 runbooks build on it.

Between 04:43:45 and 04:44:57 UTC on 2026-11-14 the owner ruled that no piece of the lab may be open core: nothing whose owner holds a feature back in a paid edition (REQ-0032 sharpened; cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, and most plainly cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). OPNsense's company, Deciso, sells a Business Edition with features the community edition lacks, among them OpenID Connect sign-in. At 05:11:29 UTC the same day the owner said OPNsense is not being replaced for now (cmsg_01X43rfNYp4H1dL1V2dkfkwNUCNWkCsmp5t7rH58x9gsJH). This record writes down that choice, its limits and its way out.

## Decision Drivers

- **FOSS with no paid feature in use** (REQ-0032; the owner, 2026-11-14).
- **An exit path off the vendor** (REQ-0032): the lab's network must not depend on anything only OPNsense can hold.
- **Replaceable** (CLAUDE.md rule 6).
- **Networking first:** everything else in the lab sits behind this machine, so changing it costs the most.

## Considered Options

1. **Keep OPNsense's community edition**, and use none of the Business Edition's features.
2. **OpenWrt.**
3. **IPFire.**
4. **VyOS**, from its free rolling images or self-built LTS images.
5. **A plain Debian router** with nftables, Unbound and Ansible.

## Decision Outcome

Proposed: **option 1, for now**, the owner's choice of 2026-11-14 at 05:11:29 UTC. Options 2 to 5 are listed from the licence check only; no research batch has compared them with OPNsense on the features the lab uses, so none is ready to replace it. That comparison is what reopens this record.

Diagram: not applicable. One component is chosen, and its place in the network is drawn in STD-0002 and the home-lab spec.

### Rules

1. **Licence and edition.** OPNsense community edition, BSD-2-Clause. Its DNS resolver, Unbound, is BSD-3-Clause with no paid edition.
2. **No Business Edition feature.** The lab uses none of the features the Business Edition adds, including its OpenID Connect sign-in, its web application firewall and its central management, all three filed under Business Edition in OPNsense's own documentation. Sign-in to OPNsense through the lab's identity provider takes a free route (D-0037).
3. **Configuration in code.** VLANs, DHCP, firewall rules and DNS overrides are set from `hosts/ansible/` (role `opnsense_lab`, collection `oxlorg.opnsense`, GPL-3.0) and `hosts/terraform/home/firewall/`, never by hand in the web UI, so the inputs outlive the product.
4. **One VLAN file.** The VLAN plan stays in the shared file both tools read (`ansible/inventories/home/group_vars/all/vlans.yml`), not in OPNsense, so a replacement reads the same file.

### Consequences

- Good: no rebuild of the lab's network now; the running firewall, its code and its 22 runbooks stay valid.
- Good: the paid-edition boundary is written down, so a change that needs a Business Edition feature fails review.
- Bad: OPNsense remains a product whose company holds features back. It meets the owner's rule only because the lab uses none of them.
- Bad: the free alternatives have not been compared on fit, so the cost of leaving is not known.

### Confirmation

- No file in `hosts/` installs or configures a Business Edition plugin or licence.
- A reviewing agent checks every OPNsense change against rule 2.

### Exit path

The lab's network inputs (the VLAN file, the firewall rules in role `opnsense_lab`, DHCP ranges and DNS overrides) are in code. A replacement re-implements the same inputs with its own tool; the VLAN plan and addresses (STD-0002) do not change.

## Pros and Cons of the Options

### Option 1: OPNsense community edition

- Good: already built, coded and documented.
- Bad: open core; Deciso's OpenID Connect sign-in is in the Business Edition only, and the one third-party plugin found for the community edition carries no licence.

### Option 2: OpenWrt

- Good: GPL-2.0; no paid edition found in the check.
- Bad: its paid side, features and fit for a virtual machine router were not checked.

### Option 3: IPFire

- Good: its project says all its software is free.
- Bad: its licence page was not opened; fit not checked.

### Option 4: VyOS

- Good: vyos-1x is LGPL-2.1; anyone may build LTS images.
- Bad: tested LTS images are sold by subscription, a paid channel for the same code; fit not checked.

### Option 5: Debian router

- Good: every part free; no vendor.
- Bad: no web UI; every function is hand-built in code.

## More Information

- Evidence: [`docs/evidence/0040-keep-opnsense-community-edition-as-the-lab-router-and-firewall-for-now.md`](../evidence/0040-keep-opnsense-community-edition-as-the-lab-router-and-firewall-for-now.md).
- Related: D-0037 (sign-in to Proxmox and OPNsense through Keycloak, proposed).
