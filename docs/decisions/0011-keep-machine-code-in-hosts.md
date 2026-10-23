---
id: D-0011
title: Keep the code for every machine below Kubernetes in hosts/, one subfolder per vendor product, with Terraform modules in their own repository
status: accepted
date: 2026-10-22
decision-makers: [jon]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0008]
supersedes: []
superseded-by:
accepted-evidence:
  quote: "accept PR jonhill90/central-hub#18 7dbae2c"
  message-id: cmsg_01X43rfNYp4H1dL1V2dkfkwN9nbb2Y5bBnkgfrLDFWMVnS
  timestamp: 2026-10-22T07:15:17Z
  approved-commit: 7dbae2cce2fbb02d5bfdf0e632a363f39f43bb4c
  merged: not yet; Jon merges PR #18, which carries this evidence commit on top of the approved commit
  quote-check: the drafting agent read the message in the repo layout thread at 2026-10-22T07:15Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
legacy-id: []
revisit-when: a second machine-building vendor product joins Terraform; the Terraform structure research names the runnable folders; or a machine kind appears that is neither a VM nor bare metal
---

# Keep the code for every machine below Kubernetes in hosts/, one subfolder per vendor product, with Terraform modules in their own repository

## Context and Problem Statement

D-0008 names the root folder `hosts/` as "machines below Kubernetes". It doesn't say what goes inside that folder, or where machines go when a cloud provider or a hypervisor runs them.

On 2026-10-20 at 03:03 UTC Jon wrote: "I dont want to clickops anything in the proxmox. So it seems we need to think about where it will go in the central hub. Along with things like vps or azure vms, aws ecs, my proxmox vms, future stuff."

## Decision Drivers

- **No click-ops.** Every machine is created and configured from code in this repository.
- **D-0008 rule 3.** Root folders are named for their job. A vendor product is never a root folder name, apart from the stated `kubernetes/` exception.
- **Replaceable** (REQ-0011). Swapping a vendor product should replace one folder, not rename a root folder.
- **Public repository** (CLAUDE.md rule 4). Single machine addresses and hostnames never go here. STD-0002 (proposed) holds the rule for addresses.

## Considered Options

1. **`hosts/` holds every machine below Kubernetes, wherever it runs, with one subfolder per vendor product** (`hosts/terraform/`, `hosts/ansible/`).
2. **One root folder per vendor product** (`terraform/`, `ansible/`). This is common in public repositories (Research repo, RL4 `R1-design-independent.md` line 122; not counted).
3. **A root `infra/` folder**, as Jon's earlier Hill90 repository used (Research repo, RL2 `S3-jon-repos.md`).

## Decision Outcome

Chosen option: **1**. Jon said yes to keeping `hosts/` on 2026-10-20 at 03:25 UTC ("host its is"). In the same message he said Terraform modules will be kept in another repository. He said yes to `terraform/` as a vendor-product subfolder name on 2026-10-19 at 03:51 UTC, in his review of the organize-repository skill changes (item 9). Jon accepted this record under D-0001 on 2026-10-22 at 07:15 UTC.

```
central-hub/
├── hosts/                     machines below Kubernetes (D-0008)
│   ├── terraform/             creates the machines: VPS, hypervisor VMs, cloud VMs
│   │   └── <runnable folders> one per place; name and split not decided here
│   └── ansible/               configures the OS on them; each machine pulls
└── kubernetes/clusters/<role>/   the clusters that run on those machines
```

### Rules

1. **What `hosts/` holds.** Code for every machine below Kubernetes goes in `hosts/`, whoever runs the machine. That covers machines Jon owns, VPS machines, VMs on his own hypervisor, and cloud VMs.
2. **One subfolder per vendor product.** Each vendor product that creates or configures machines gets one subfolder in its own native layout, named for the product, for example `hosts/terraform/` or `hosts/ansible/`. Replacing the product replaces only that subfolder.
3. **Terraform modules live in their own repository.** This repository keeps only the folders that are run. Each one points at a tagged version of the modules repository.
4. **Not machines, not `hosts/`.** A managed container service with no machines to manage, such as AWS ECS, doesn't go in `hosts/`. It gets its own capability folder when it is first used (D-0008 rule 5).
5. **No private values.** Hostnames and single machine addresses stay blanks, filled in at apply time (CLAUDE.md rule 4; STD-0002, proposed).

### Not decided here

- the name and split of the runnable Terraform folders inside `hosts/terraform/` (`stacks/`, `envs/` or something else). This waits on the Terraform structure research;
- the name and home of the modules repository;
- which Terraform provider builds the hypervisor VMs;
- the layout inside `hosts/ansible/`;
- the folders inside `docs/`, which the documentation folder map work covers.

### Consequences

- Good: one place to look for anything that makes or changes a machine.
- Good: swapping Terraform or Ansible for another product replaces one subfolder, and every root folder name stays the same.
- Bad: two vendor-product names appear one level down, so the "job, not product" naming applies only at the root.
- Bad: a change to a module needs a tagged release in a second repository before this repository can use it.
- Neutral: none of these folders exists yet. Each one appears with its first file.

### Confirmation

- A reviewing agent checks each PR that adds a folder under `hosts/` against these rules.
- No `modules/` folder for Terraform appears in this repository.

## Pros and Cons of the Options

### 2. One root folder per vendor product
- Good: newcomers and agents trained on public repositories expect it.
- Bad: replacing a product renames a root folder, against D-0008 rule 3.

### 3. A root `infra/` folder
- Good: Jon has used it before.
- Bad: nearly everything in this repository is infrastructure, so the name doesn't say what is inside.
- Bad: `kubernetes/infrastructure/` already uses the same word for cluster add-ons, in Flux's layout.

## More Information

- Research behind it: Research repo, `labs/central-hub/repo-layout/rl4/` (`RULES-v4.md` N2, N5, F1; `SYNTHESIS.md`, "Where machine and VM code goes").
- Related records: D-0001, D-0008. Related standard: STD-0002 (proposed).

## Corrections

- **2026-10-23** (requirement IDs respelled under D-0014): 1 requirement ID renamed, `SR11` to `REQ-0011`. Before: `SR11`; after: `REQ-0011`, and the same for each pair listed. Reason: D-0014 retires the `SR` spelling and its rule 5 renames live references in place; no decision changes. Approval: Jon, "approve PR jonhill90/central-hub#23 cabb14e" (message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, 2026-10-23T04:04:08Z); approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23).
