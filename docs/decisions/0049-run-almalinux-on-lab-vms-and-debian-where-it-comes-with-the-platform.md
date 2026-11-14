---
id: D-0049
title: Run AlmaLinux 10 on the lab's Linux virtual machines, and Debian only where it comes with the platform (the Proxmox host and its container template)
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
revisit-when: c1 moves to an immutable OS such as Talos; AlmaLinux or Debian changes its licence, governance or free availability; the owner rules on whether a sponsor's paid FIPS-validated packages make AlmaLinux fail his rule of 2026-11-14; a research batch compares Linux distributions for the lab's machines; or one distribution everywhere is wanted
---

# Run AlmaLinux 10 on the lab's Linux virtual machines, and Debian only where it comes with the platform (the Proxmox host and its container template)

## Context and Problem Statement

The lab runs two Linux distributions.

- **AlmaLinux 10** runs on every Linux virtual machine made from code except the Talos rehearsal's: c1's nodes, the agent box, the CI runner, the desktop and the secrets store. They all come from one AlmaLinux 10 GenericCloud image, pinned by URL and checksum in `hosts/terraform/home/k8s/variables.tf`. The firewall VM runs OPNsense, which is not Linux (D-0040). The Talos Linux node VMs of the Talos rehearsal (`hosts/terraform/home/k8s-talos/`) are outside this record: they try Talos beside c1 and are not clones of the AlmaLinux template.
- **Debian** runs under Proxmox itself (D-0047), and in the remote-access container, which is made from Proxmox's Debian 13 template (`hosts/terraform/home/remote-access/`).

The owner's words this rests on:

- 2026-10-15 at 21:32:54 UTC: AlmaLinux 10 as the node OS, for the earlier VPS cluster.
- 2026-10-26 at 07:32 UTC: yes to pinning the node image (cmsg_01X43rfNYp4H1dL1V2dkfkwNJXymR9pUCUdxGTMov12twH).

At main d9139e7, 26 files in `hosts/`, 7 runbooks and 2 records name AlmaLinux, and 10 files, 6 runbooks and 1 record name Debian. No decision record chose either.

Between 04:43:45 and 04:44:57 UTC on 2026-11-14 the owner ruled that no piece of the lab may hold something back behind a paywall (cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). STD-0006 rule 2 turns that into a test: a component fails when its owner or lead company sells an edition that holds features back from the free one, and selling support, hosting, training or tested builds of the same code is allowed. This record writes down both distributions, their paid sides, and how to leave.

## Decision Drivers

- **FOSS with nothing held back behind a paywall** (REQ-0032; the owner, 2026-11-14; STD-0006 rule 2).
- **One way to build each kind of machine:** one pinned image, one set of roles.
- **Replaceable** (CLAUDE.md rule 6).

## Considered Options

1. **AlmaLinux 10 on Linux VMs; Debian only where the platform brings it.**
2. **Debian everywhere.**
3. **AlmaLinux everywhere**, including the container.

## Decision Outcome

Proposed: **option 1**, the owner's choice of 2026-10-15 for the nodes, and what runs. Debian under Proxmox is not a choice the lab makes, because Proxmox ships on it. The container's template is Proxmox's own. Options 2 and 3 were not compared on fit.

Diagram: not applicable. Two operating systems, each on the machines listed above.

### Do the sponsors' paid offers make AlmaLinux fail?

The owner's words of 04:44:57 UTC reach further than STD-0006's register row, so this is weighed openly.

- **The OS.** The AlmaLinux OS Foundation calls AlmaLinux "An Open Source, community owned and governed, forever-free enterprise Linux distribution". It has no paid edition of its own.
- **What sponsors sell.** Its support page lists sponsors' offers:
  - TuxCare: support, help with certification, FIPS 140-3 compliance and hardening;
  - Cybertrust Japan: support;
  - Fujitsu: fixes for specific minor releases for up to 10 years.
- **The FIPS packages.** TuxCare's documentation says its Extended Security Updates include "the full suite of five FIPS-validated modules" and that the product "unlocks commercial use of the FIPS-validated packages". TuxCare is AlmaLinux's founding sponsor.
- **The reading.** Support and longer fixes are support and tested builds, which STD-0006 allows; the register counts AlmaLinux as a pass and says that reading is the owner's to overturn. FIPS-validated packages whose commercial use needs a paid licence are closer to a held-back feature, even though they are sold by a sponsor rather than by the Foundation, and the lab does not use them.
- **So this record stays `proposed`.** Whether a founding sponsor's paid FIPS packages count as a paywall is the owner's call, and `revisit-when` names it.
- **Debian** has no paid side: its social contract says "We promise that the Debian system and all its components will be free".

### Rules

1. **Licence and edition.** AlmaLinux 10 from the AlmaLinux OS Foundation's own repositories; Debian from Debian's and Proxmox's.
2. **Pinned images.** VM images are pinned to one build with its checksum (STD-0003), and change only by a pull request.
3. **No paid add-on.** No machine uses a paid support channel, a sponsor's extended-update or FIPS repository, or any other vendor add-on repository.

### Consequences

- Good: no change; both are free, and neither has a paid edition of its own.
- Bad: AlmaLinux's FIPS-validated packages and longer fixes are sold by its sponsors, so a need for either would mean paying or moving.
- Bad: two distributions, two package managers and two sets of security feeds to follow.

### Confirmation

- Every VM in the `k8s`, `ci-runner`, `desktop`, `jumpbox` and `secrets-store` folders of `hosts/terraform/home/` clones a template made from the pinned AlmaLinux image.
- No role adds a TuxCare, Cybertrust or Fujitsu repository.

### Exit path

The machines are made from one image variable and configured by Ansible roles. A move to another distribution changes the image, the package names in the roles and the repository files; the roles' structure stays.

## Pros and Cons of the Options

### Option 1: AlmaLinux on Linux VMs, Debian where it comes with the platform

- Good: both free; matches what runs; c1's nodes track an enterprise-style release.
- Bad: two distributions; a sponsor sells the FIPS packages, weighed above.

### Option 2: Debian everywhere

- Good: one distribution, the same as the host; no paid side.
- Bad: rewrites the node roles; not compared.

### Option 3: AlmaLinux everywhere

- Good: one distribution for every guest.
- Bad: a custom container template to maintain; not compared.

## More Information

- Evidence: [`docs/evidence/0049-run-almalinux-on-lab-vms-and-debian-where-it-comes-with-the-platform.md`](../evidence/0049-run-almalinux-on-lab-vms-and-debian-where-it-comes-with-the-platform.md).
- Related: D-0040 (OPNsense), D-0047 (Proxmox VE), STD-0003, STD-0006 and its register (`docs/standards/components.yaml`).
