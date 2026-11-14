---
id: D-0047
title: Keep Proxmox VE as the lab's hypervisor, on its free no-subscription repositories, with Incus as the named alternative
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
revisit-when: Proxmox moves a feature the lab uses behind a subscription; the no-subscription repositories stop or change terms; the owner rules that a paid channel of more-tested updates is a paywall under his rule of 2026-11-14; a research batch compares hypervisors for the lab feature by feature; or the lab moves to more than one host
---

# Keep Proxmox VE as the lab's hypervisor, on its free no-subscription repositories, with Incus as the named alternative

## Context and Problem Statement

Every lab machine runs on one Proxmox VE host: OPNsense, c1's nodes, the CI runner, the agent box, the desktop and the remote-access container. Proxmox was installed by hand on the lab host ([set-up-proxmox-host.md](../runbooks/set-up-proxmox-host.md)). On 2026-10-20 at 00:39 UTC the owner said c1's control plane and workers would run locally in Proxmox, for now. On 2026-10-25 at 05:27 and 05:59 UTC he said yes to Terraform-style code creating the Proxmox VMs, with the `bpg/proxmox` provider (D-0011); the lab runs that code with OpenTofu.

At main 3d3bcf1, 169 files in 88 `hosts/` folders and 29 runbooks name Proxmox, and so do 16 records from D-0002 to D-0045. They build on it, but no decision record chose it.

Proxmox Server Solutions sells subscriptions. Between 04:43:45 and 04:44:57 UTC on 2026-11-14 the owner ruled that no piece of the lab may hold something back behind a paywall (cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). STD-0006, which he accepted at 06:30:41 UTC the same day, turns that into its rule 2: a component fails when a paid edition holds features back, and selling support, hosting, training or tested builds of the same code is allowed. Its register already lists Proxmox VE as a pass. This record writes down the choice, the paid side, and why it passes.

## Decision Drivers

- **FOSS with nothing held back behind a paywall** (REQ-0032; the owner, 2026-11-14; STD-0006 rule 2).
- **Replaceable** (CLAUDE.md rule 6): the lab's machines are made by code against the hypervisor's API.
- **Already running:** every layer above it would be rebuilt by a change.

## Considered Options

1. **Proxmox VE** on its no-subscription repositories.
2. **Incus.**

## Decision Outcome

Proposed: **option 1**. Option 2 is the named alternative; it has not been compared on fit.

### Is the paid repository a paywall?

The owner's words of 04:44:57 UTC reach further than features, so this is weighed openly.

- **What is paid.** A subscription buys support tickets and access to the Enterprise Repository. Proxmox's documentation says that repository "contains the most stable packages and is suitable for production use". The no-subscription repository "can be used for testing and non-production use", because its packages "are not always as heavily tested and validated".
- **What is not paid.** Proxmox's pricing page answers "Are Proxmox VE features limited by subscription level?" with "No", and says "all other Proxmox VE features are available at every level". The free repository carries the same software, tested less. Without a key, the web UI also shows a notice at sign-in, which the set-up runbook describes.
- **The reading.** The paid side is tested builds of the same code plus support, which STD-0006 rule 2 names as allowed, and nothing the lab runs is held back. So this record counts Proxmox VE as a STD-0006 pass, as the register does.
- **The doubt.** A reader of the owner's words could still call a paid, more-tested update channel a paywall. That reading would also fail AlmaLinux, whose sponsors sell fixes for specific minor releases (the register's AlmaLinux row). Only the owner can overturn the reading, and `revisit-when` names it.

### Rules

1. **Licence and edition.** Proxmox VE, AGPL-3.0-or-later, from the `pve-no-subscription` repositories, with no subscription key.
2. **Every machine by code.** VMs and containers are made by OpenTofu through the Proxmox API (D-0011), so the hypervisor's own settings are the only part not in a portable form.
3. **The paid channel.** Paying for the Enterprise Repository is the owner's call, because it is money (D-0042 rule 6). It changes no feature.

### Consequences

- Good: no change to the lab.
- Good: no feature is behind the subscription, as the vendor states.
- Bad: the free repositories are, in Proxmox's words, for testing and non-production use, and their updates are tested less than the paid ones.
- Bad: the OpenTofu provider and Ansible roles are written for Proxmox's API, so a move rewrites them.

### Confirmation

- No `hosts/` file or runbook adds a subscription key or the enterprise repository.

### Exit path

The machines are in OpenTofu folders and Ansible roles. A move to Incus (Apache-2.0) replaces the provider and the host roles. The guests' operating systems, their addresses (STD-0002) and the Ansible roles for what runs inside them stay.

## Pros and Cons of the Options

### Option 1: Proxmox VE

- Good: AGPL-3.0-or-later; every feature free; running.
- Bad: paid tested-updates channel; one host.

### Option 2: Incus

- Good: Apache-2.0. The Incus docs say commercial support is available from Zabbly for its packages, and name no paid-only feature. Zabbly's own pricing was not checked.
- Bad: not compared on fit; every machine's code would change.

## More Information

- Evidence: [`docs/evidence/0047-keep-proxmox-ve-as-the-lab-hypervisor-on-its-free-repositories.md`](../evidence/0047-keep-proxmox-ve-as-the-lab-hypervisor-on-its-free-repositories.md).
- Related: STD-0006 and its register (`docs/standards/components.yaml`), D-0011, STD-0002.
