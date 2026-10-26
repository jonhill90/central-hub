---
id: D-0011
title: Keep the code for every machine below Kubernetes in hosts/, one subfolder per vendor product, and no Terraform modules of its own until code is reused
status: accepted
date: 2026-10-22
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0008]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-22T07:15:17Z
  approved-commit: 7dbae2cce2fbb02d5bfdf0e632a363f39f43bb4c
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwN9nbb2Y5bBnkgfrLDFWMVnS
  approval-names: "PR #18 and head 7dbae2c, in the message itself"
  check: the drafting agent read the message in the repo layout thread at 2026-10-22T07:15Z, and the recorded wording matched it exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: PR #18 merged at 2026-10-22T07:16Z as 36d6a90, with this evidence commit on top of the approved commit
revisit-when: a second machine-building vendor product joins Terraform; the Terraform structure research names the runnable folders; or a machine kind appears that is neither a VM nor bare metal
---

# Keep the code for every machine below Kubernetes in hosts/, one subfolder per vendor product, and no Terraform modules of its own until code is reused

## Context and Problem Statement

D-0008 names the root folder `hosts/` as "machines below Kubernetes". It doesn't say what goes inside that folder, or where machines go when a cloud provider or a hypervisor runs them.

On 2026-10-20 at 03:03 UTC the owner asked where the code for the Proxmox hypervisor should go in central-hub, along with VPS machines, cloud VMs, cloud container services and machines still to come. The rule it serves is PRD goal 6: everything is controllable from this repository, and one-time console steps at the start are fine.

On 2026-10-25 at 02:53 UTC the owner said yes to the proposed home for configuration management code: it lives in this repository, under `hosts/`. At 05:27 UTC he said yes to the proposed split for the home lab: Terraform creates the Proxmox VMs and networks, and Ansible configures the Proxmox host and the settings of the OPNsense firewall. At 05:59 UTC he said yes to the proposed Terraform provider, `bpg/proxmox`, and at 06:04 UTC to the proposed Ansible collection for the firewall, `oxlorg.opnsense`. On 2026-10-26 at 00:18 UTC he said yes to the proposed layout inside `hosts/ansible/`.

## Decision Drivers

- **Controllable from this repository** (PRD goal 6). After one-time console steps at the start, every machine is created and configured from code here. Each job is first done by hand from a manual runbook, and its code follows (D-0012 "Manual first").
- **D-0008 rule 3.** Root folders are named for their job. A vendor product is never a root folder name, apart from the stated `kubernetes/` exception.
- **Replaceable** (REQ-0011). Swapping a vendor product should replace one folder, not rename a root folder.
- **Public repository** (CLAUDE.md rule 4). Single machine addresses and hostnames never go here. STD-0002 holds the rule for addresses.

## Considered Options

1. **`hosts/` holds every machine below Kubernetes, wherever it runs, with one subfolder per vendor product** (`hosts/terraform/`, `hosts/ansible/`).
2. **One root folder per vendor product** (`terraform/`, `ansible/`). This is common in public repositories (batch RB-0036; not counted).
3. **A root `infra/` folder**, as the earlier Hill90 repository used (batch RB-0033).

## Decision Outcome

Chosen option: **1**. The owner said yes to keeping `hosts/` on 2026-10-20 at 03:25 UTC. He said yes to `terraform/` as a vendor-product subfolder name on 2026-10-19 at 03:51 UTC, in his review of the organize-repository skill changes (item 9). The owner accepted this record under D-0001 on 2026-10-22 at 07:15 UTC. On 2026-10-26 at 04:51 UTC he said yes to the proposed rule for Terraform modules (rule 3): none of our own yet, and shared code stays in this repository until another repository needs it.

```
central-hub/
├── hosts/                     machines below Kubernetes (D-0008)
│   ├── terraform/             creates the machines: VPS, hypervisor VMs and networks, cloud VMs
│   │   ├── <runnable folders> one per place; split inside a place not decided here
│   │   └── modules/<name>/    only once code is reused (rule 3)
│   └── ansible/               configures the OS on them, and the firewall's settings
│       ├── inventories/<place>/
│       ├── playbooks/
│       └── roles/
└── kubernetes/clusters/<role>/   the clusters that run on those machines
```

### Rules

1. **What `hosts/` holds.** Code for every machine below Kubernetes goes in `hosts/`, whoever runs the machine. That covers machines the owner owns, VPS machines, VMs on his own hypervisor, and cloud VMs.
2. **One subfolder per vendor product.** Each vendor product that creates or configures machines gets one subfolder in its own native layout, named for the product, for example `hosts/terraform/` or `hosts/ansible/`. Replacing the product replaces only that subfolder.
3. **No Terraform modules of our own until code is reused.** A runnable folder holds its own resources. Code that two or more runnable folders use goes in `hosts/terraform/modules/<name>/`, called by a local path. It moves to its own repository, called by a tagged version, only when another repository needs it. A module is written only when it bundles real logic, such as a whole VM, and never as a thin wrapper around one resource, as HashiCorp's module guidance advises.
4. **Not machines, not `hosts/`.** A managed container service with no machines to manage, such as AWS ECS, doesn't go in `hosts/`. It gets its own capability folder when it is first used (D-0008 rule 5).
5. **No private values.** Hostnames and single machine addresses stay blanks, filled in at apply time (CLAUDE.md rule 4; STD-0002).
6. **Home-lab tools.** Terraform builds the Proxmox VMs and networks with the `bpg/proxmox` provider. Ansible configures the OPNsense firewall's settings with the `oxlorg.opnsense` collection.
7. **Ansible layout.** `hosts/ansible/` holds one inventory folder per place (`inventories/<place>/`), one `playbooks/` folder and one plain `roles/` folder.

### Not decided here

- the name and split of the runnable Terraform folders inside `hosts/terraform/`, for example one folder per workload inside each place (`hosts/terraform/<place>/<workload>/`). Research batch RB-0083 sets out the options;
- the name and home of a modules repository, once another repository needs one;
- whether Ansible runs by push (a runner connects to each machine) or by pull (each machine runs it on itself on a timer).

### Consequences

- Good: one place to look for anything that makes or changes a machine.
- Good: swapping Terraform or Ansible for another product replaces one subfolder, and every root folder name stays the same.
- Bad: two vendor-product names appear one level down, so the "job, not product" naming applies only at the root.
- Bad: until code is reused, two runnable folders may hold similar resources written twice.
- Good: a change to shared code needs no release in a second repository while only this repository uses it.
- Neutral: none of these folders exists yet. Each one appears with its first file.

### Confirmation

- A reviewing agent checks each PR that adds a folder under `hosts/` against these rules.
- Each folder in `hosts/terraform/modules/` is called by two or more runnable folders and holds more than one resource.

## Pros and Cons of the Options

### 2. One root folder per vendor product
- Good: newcomers and agents trained on public repositories expect it.
- Bad: replacing a product renames a root folder, against D-0008 rule 3.

### 3. A root `infra/` folder
- Good: the owner has used it before.
- Bad: nearly everything in this repository is infrastructure, so the name doesn't say what is inside.
- Bad: `kubernetes/infrastructure/` already uses the same word for cluster add-ons, in Flux's layout.

## More Information

- **Evidence:** no research batch of its own. Its naming rules come from the repository layout batch RB-0036, which D-0008 rests on: [../research/0008-name-the-prd-specs-and-root-folders.md](../research/0008-name-the-prd-specs-and-root-folders.md), finding 2.
- **Modules guidance:** HashiCorp, "Creating modules", the section on when to write a module: <https://developer.hashicorp.com/terraform/language/modules/develop#when-to-write-a-module>, read in research batch RB-0083 on 2026-10-25.
- Related records: D-0001, D-0008. Related standard: STD-0002.
