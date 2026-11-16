---
id: D-0048
title: Build the lab's machines with OpenTofu and configure them with ansible-core, using no paid automation platform
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
  approval-ref: the orchestrator thread's message to the Plan thread of 2026-11-16T06:12:51Z recording the reviewer's clearance (06:11:14Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNJVnsFS1px4pXrQYEDpvTzT) and the passes of Councils A (06:09:04Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNJeqFBSqTpKTyeeQWCYMffJ), B (D-0048, 06:11:44Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNN9pFtKrpSq71CZkHhPAL1k) and C (06:09:32Z, cmsg_01X43rfNYp4H1dL1V2dkfkwNXB561ABmu2eMeFPN4kJywC) for this record as merged at 135f589, each saying acceptance by the agents' pass under D-0042 rule 3 is fine; it reached the Plan thread as a thread relay, which carries no message id
  approval-names: "each pass names D-0048 and commit 135f5895419d841b489ec9b159a940126c34acff, the squash merge of PR #366, the last change to this record's text"
  check: "approved-by is agents under D-0042 rules 1 and 3, because this record's own line says it becomes accepted once the pick is in use and passes STD-0006, after the owner kept it as written on card cmsg_01X43rfNYp4H1dL1V2dkfkwN1TjGnbUJUBa4TLNk8AL3gv (option 0, 2026-11-15T04:51:59Z); measured on main f27e322: in use (90 .tf files under hosts/terraform, 341 files under hosts/ansible, the AlmaLinux image pinned in hosts/terraform/home/k8s/variables.tf, Debian in hosts/terraform/home/remote-access), and OpenTofu, OpenTofu providers, Ansible, AlmaLinux and Debian are pass in docs/standards/components.yaml; waits-on is empty; the merge verdict's amend pattern finds no hit, so D-0042 rule 11 does not send it to the owner. This PR changes only this record's status, date and accepted-evidence and its row in the decisions index, which the reviewer checks against 135f589 (D-0001)"
  merged: not yet; a follow-up PR fills this in after the merge (D-0001)
revisit-when: c1 moves to an immutable OS whose own API replaces Ansible on the nodes; OpenTofu or ansible-core changes licence or governance; the lab needs certified content, a web UI, an API or a scheduler for runs that only a paid product offers; the owner rules on whether Red Hat's paid platform makes Ansible fail his rule of 2026-11-14; or a research batch compares the tools on fit
---

# Build the lab's machines with OpenTofu and configure them with ansible-core, using no paid automation platform

## Context and Problem Statement

`hosts/` holds the lab as code in two tools (D-0011, STD-0004). OpenTofu makes the machines, networks, tokens and cloud resources (`hosts/terraform/`). Ansible configures what runs on them (`hosts/ansible/`). At main 6f777df that is 90 `.tf` files in 15 run folders and 303 files under `hosts/ansible/`. 24 runbooks name OpenTofu and 51 name Ansible; 5 records name OpenTofu and 14 name Ansible.

The owner's words this rests on:

- 2026-10-17 at 23:07 UTC: yes to trying Ansible as the configuration tool for his first real build.
- 2026-10-25 at 05:27 UTC: yes to Terraform-style code for the Proxmox VMs and networks, and Ansible for the host and OPNsense (cmsg_01X43rfNYp4H1dL1V2dkfkwNRFZJcS1CMSehtz9iE5YMRA, D-0011).
- 2026-10-25 at 17:47 UTC: yes to keeping the lab's OpenTofu state as local files for now.
- 2026-10-27 at 02:49 UTC: everything must be deterministic, idempotent code, with no clicking and no one-off commands.

No record chose OpenTofu or Ansible against alternatives or stated their licences.

Between 04:43:45 and 04:44:57 UTC on 2026-11-14 the owner ruled that no piece of the lab may hold something back behind a paywall (cmsg_01X43rfNYp4H1dL1V2dkfkwNR46AufLXRC146Xo4CSXG6t, cmsg_01X43rfNYp4H1dL1V2dkfkwNQV7TsveqXKdLbddnuYc8v7, cmsg_01X43rfNYp4H1dL1V2dkfkwN5A1ezB3rCi7zkVswXeZkB4). STD-0006 rule 2 turns that into a test: a component fails when its lead company sells an edition that holds features back from the free one, and selling support, hosting, training or tested builds of the same code is allowed. HashiCorp's Terraform, which OpenTofu forked from, is no longer under an open-source licence. Red Hat sells Ansible Automation Platform around Ansible. This record writes down the two tools, their licences and their paid sides.

## Decision Drivers

- **FOSS with nothing held back behind a paywall** (REQ-0032; the owner, 2026-11-14; STD-0006 rule 2).
- **Everything in deterministic, idempotent code** (the owner, 2026-10-27).
- **Replaceable** (CLAUDE.md rule 6).

## Considered Options

1. **OpenTofu and ansible-core.**
2. **Terraform and ansible-core.**
3. **OpenTofu and Red Hat Ansible Automation Platform.**

## Decision Outcome

Proposed: **option 1**, what runs. Option 2 is ruled out because Terraform is under the Business Source License. Option 3 is a paid product.

Diagram: not applicable. The order between the folders is written in `hosts/README.md` and STD-0004.

### Does Red Hat's paid platform make Ansible fail?

The owner's words of 04:44:57 UTC reach further than STD-0006's register row, so this is weighed openly.

- **What Red Hat sells.** Its comparison page calls Ansible Automation Platform "an end-to-end automation platform that combines 20+ community projects" sold "through an enterprise subscription". Its list of enterprise capabilities includes a web UI and API (automation controller), event-driven automation, role-based access and audit, a private content hub, support, and two things with no community counterpart named on that page: Red Hat Ansible Certified Content, and generative AI assistants.
- **What has a free upstream.** The same page describes the free alternative as "a set of upstream projects", needing "manual integration of open-source GUI and API components". The controller's upstream, AWX, is Apache-2.0.
- **What the lab uses.** Only `ansible-core` from PyPI and three collections from Galaxy (`oxlorg.opnsense`, `community.general`, `ansible.posix`), all GPL-3.0. It uses no certified content and no AI assistant.
- **The reading.** OpenTofu is a clear pass: a Linux Foundation project with no paid edition. For Ansible, most of the platform is support and integrated builds of open upstreams, which STD-0006 allows. Certified content and the AI assistants, though, are sold only with the subscription as far as the page shows. The register's Ansible row does not mention them.
- **So this record stays `proposed`.** Whether paid-only content and assistants around a free core count as a paywall is the owner's call, and `revisit-when` names it.
- **The owner's call (2026-11-15).** At 04:51:59 UTC, on card `cmsg_01X43rfNYp4H1dL1V2dkfkwN1TjGnbUJUBa4TLNk8AL3gv`, the owner chose to keep this record and D-0049 as written, with the lab using only the free parts. The status still follows the pick-records rule: `accepted` once the pick is in use and passes STD-0006.

### Rules

1. **Licences.** OpenTofu, MPL-2.0. Providers: `bpg/proxmox`, `hashicorp/azurerm`, `hashicorp/azuread`, `hashicorp/local` and `hashicorp/time` are MPL-2.0, `tailscale/tailscale` is MIT, and `cloudflare/cloudflare` is Apache-2.0 (D-0045). ansible-core and the collections `oxlorg.opnsense`, `community.general` and `ansible.posix` are GPL-3.0.
2. **Only the free cores.** The controller installs `ansible-core` from `requirements.txt` and the collections from `requirements.yml`, both pinned. It never installs Ansible Automation Platform, certified content or Terraform.
3. **State and secrets** stay where D-0038 and the runbooks put them; this record changes neither.

### Consequences

- Good: no change; both tools run with no paid part.
- Bad: two tools to keep current.
- Neutral: running Ansible from a web UI would need AWX or another runner set up by hand. D-0041 already runs every change through one pipeline instead.

### Confirmation

- `hosts/ansible/requirements.txt` names `ansible-core`, not `ansible` or an automation platform package, and `requirements.yml` names only Galaxy collections.
- No script under `hosts/` or `.github/` runs the `terraform` binary.

### Exit path

The code is plain HCL and YAML in git. Another provisioning tool reads the same inputs (the VLAN file, tfvars, inventories). The Ansible roles can run from any controller, or be replaced role by role.

## Pros and Cons of the Options

### Option 1: OpenTofu and ansible-core

- Good: both free; running; OpenTofu is governed by a foundation.
- Bad: Ansible's lead company sells content and assistants around it, weighed above.

### Option 2: Terraform and ansible-core

- Good: the original tool.
- Bad: Business Source License, not open source.

### Option 3: OpenTofu and Ansible Automation Platform

- Good: a web UI, API, role-based access, audit and support.
- Bad: a paid product.

## More Information

- Evidence: [`docs/evidence/0048-build-the-lab-with-opentofu-and-ansible-core.md`](../evidence/0048-build-the-lab-with-opentofu-and-ansible-core.md).
- Related: D-0011, STD-0004, STD-0006 and its register (`docs/standards/components.yaml`), D-0041.
