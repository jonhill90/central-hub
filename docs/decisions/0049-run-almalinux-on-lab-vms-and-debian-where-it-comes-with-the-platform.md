---
id: D-0049
title: Run AlmaLinux 10 on the lab's Linux virtual machines, and Debian only where it comes with the platform (the Proxmox host and its container template)
status: accepted
date: 2026-11-16
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: agents
  approved-at: 2026-11-16T06:12:51Z
  approved-commit: 135f5895419d841b489ec9b159a940126c34acff
  approval-ref: the orchestrator thread's message to the Plan thread of 2026-11-16T06:12:51Z recording the reviewer's clearance (06:11:14Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNJVnsFS1px4pXrQYEDpvTzT) and the passes of Councils A (06:09:04Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNJeqFBSqTpKTyeeQWCYMffJ), B (D-0049, 06:11:39Z, cmsg_01X43rfNYp4H1dL1V2dkfkwN6An4874HcSoSaGLqkmv6hz) and C (06:09:32Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNXB561ABmu2eMeFPN4kJywC) for this record as merged at 135f589, each saying acceptance by the agents' pass under D-0042 rule 3 is fine; it reached the Plan thread as a thread relay, which carries no message id
  approval-names: "each pass names D-0049 and commit 135f5895419d841b489ec9b159a940126c34acff, the squash merge of PR #366, the last change to this record's text"
  check: "approved-by is agents under D-0042 rules 1 and 3, because this record's own line says it becomes accepted once the pick is in use and passes STD-0006, after the owner kept it as written on card cmsg_01X43rfNYp4H1dL1V2dkfkwN1TjGnbUJUBa4TLNk8AL3gv (option 0, 2026-11-15T04:51:59Z); measured on main f27e322: in use (90 .tf files under hosts/terraform, 341 files under hosts/ansible, the AlmaLinux image pinned in hosts/terraform/home/k8s/variables.tf, Debian in hosts/terraform/home/remote-access), and OpenTofu, OpenTofu providers, Ansible, AlmaLinux and Debian are pass in docs/standards/components.yaml; waits-on is empty; the merge verdict's rule-11 pattern finds no hit, so D-0042 rule 11 does not send it to the owner. This PR changes only this record's status, date and accepted-evidence and its row in the decisions index, which the reviewer checks against 135f589 (D-0001)"
  merged: "PR #394 squash-merged at head bea263e as 01d100c, whose commit time is 2026-11-16T06:28:29Z (GitHub's merged_at for the PR is 06:28:30Z); the follow-up PR that adds this line changes nothing else in this record (D-0001)"
revisit-when: c1 moves to an immutable OS such as Talos; AlmaLinux or Debian changes its licence, governance or free availability; the owner rules that a sponsor's paid FIPS offer makes AlmaLinux fail his rule of 2026-11-14; the lab needs FIPS-validated cryptography; a research batch compares Linux distributions for the lab's machines; or one distribution everywhere is wanted
---

# Run AlmaLinux 10 on the lab's Linux virtual machines, and Debian only where it comes with the platform (the Proxmox host and its container template)

## Context and Problem Statement

The lab runs two Linux distributions.

- **AlmaLinux 10** runs on every Linux virtual machine made from code except the Talos rehearsal's: c1's nodes, the agent box, the CI runner, the desktop and the secrets store. They all come from one AlmaLinux 10 GenericCloud image, pinned by URL and checksum in `hosts/terraform/home/k8s/variables.tf`. The firewall VM runs OPNsense, which is not Linux (D-0040). The Talos Linux node VMs of the Talos rehearsal (`hosts/terraform/home/k8s-talos/`) are outside this record: they try Talos beside c1 and are not clones of the AlmaLinux template.
- **Debian** runs under Proxmox itself (D-0047), in the remote-access container, which is made from Proxmox's Debian 13 template (`hosts/terraform/home/remote-access/`), and in CT 259, the jumpbox rehearsal's container. CT 259 is an unprivileged Debian 13 container made by the jumpbox rehearsal kit, whose code is not in this repository; agents never touch it (D-0035 rule 2, `hosts/terraform/home/bootstrap/agent-access.sh`).

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
- **AlmaLinux's own FIPS page.** The Foundation's page says the validation was sponsored and paid for by TuxCare, that anyone running AlmaLinux OS 9.2 can use the validated modules at no cost for non-commercial use, from TuxCare's community repository, and that commercial use and ongoing FIPS-compliant patching come through TuxCare's paid support.
- **The reading under STD-0006 rule 2: a pass.**
  - The owner of AlmaLinux is the AlmaLinux OS Foundation, and it sells no edition. TuxCare is a sponsor, not the owner or lead company.
  - FIPS validation is a certificate on a build of named packages, which is a tested build, and rule 2 allows selling tested builds.
  - Support and longer fixes are support and tested builds too.
  - The lab does not use FIPS mode, and rule 3 below keeps every sponsor repository off its machines.
  - The register already counts AlmaLinux as a pass.
- **What would change it.** If the owner rules that a sponsor's paid FIPS offer counts as a paywall under their words of 2026-11-14, this record is revisited (`revisit-when`).
- **Why it stays proposed.** It stays proposed until the owner rules on the FIPS reading, because the register row they approved did not weigh it.
- **The owner's call (2026-11-15).** At 04:51:59 UTC, on card `cmsg_01X43rfNYp4H1dL1V2dkfkwN1TjGnbUJUBa4TLNk8AL3gv`, the owner chose to keep this record and D-0048 as written, with the lab using only the free parts; the paid FIPS offer is not used. The status still follows the pick-records rule: `accepted` once the pick is in use and passes STD-0006.
- **Debian** has no paid side: its social contract says "We promise that the Debian system and all its components will be free".

### Rules

1. **Licence and edition.** AlmaLinux 10 from the AlmaLinux OS Foundation's own repositories; Debian from Debian's and Proxmox's.
2. **Pinned images.** VM images are pinned to one build with its checksum (STD-0003), and change only by a pull request.
3. **No paid add-on.** No machine uses a paid support channel, a sponsor's extended-update or FIPS repository, or any other vendor add-on repository.

### Consequences

- Good: no change; both are free, and neither has a paid edition of its own.
- Bad: AlmaLinux's FIPS-validated packages and longer fixes are sold by its sponsors, so a need for either would mean paying or moving.
- Bad: two distributions, two package managers and two sets of security feeds to follow.
- Bad: CT 259 runs Debian 13 but is not in code here, so this repository can't rebuild it or check its image. It is a gap until the rehearsal kit's container is brought into `hosts/`.

### Confirmation

- Every VM in the `k8s`, `ci-runner`, `desktop`, `jumpbox` and `secrets-store` folders of `hosts/terraform/home/` clones a template made from the pinned AlmaLinux image.
- No role adds a TuxCare, Cybertrust or Fujitsu repository.
- CT 259 is outside this check, because it is not in code here (see Consequences).

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
