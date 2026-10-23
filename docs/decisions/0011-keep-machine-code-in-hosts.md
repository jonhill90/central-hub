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
  approved-by: owner
  approved-at: 2026-10-22T07:15:17Z
  approved-commit: 7dbae2cce2fbb02d5bfdf0e632a363f39f43bb4c
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwN9nbb2Y5bBnkgfrLDFWMVnS
  approval-names: "PR #18 and head 7dbae2c, in the message itself"
  check: the drafting agent read the message in the repo layout thread at 2026-10-22T07:15Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; Jon merges PR #18, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: a second machine-building vendor product joins Terraform; the Terraform structure research names the runnable folders; or a machine kind appears that is neither a VM nor bare metal
---

# Keep the code for every machine below Kubernetes in hosts/, one subfolder per vendor product, with Terraform modules in their own repository

## Context and Problem Statement

D-0008 names the root folder `hosts/` as "machines below Kubernetes". It doesn't say what goes inside that folder, or where machines go when a cloud provider or a hypervisor runs them.

On 2026-10-20 at 03:03 UTC Jon said that nothing on the Proxmox hypervisor should be set up by hand, and asked where its code should go in central-hub, along with VPS machines, cloud VMs, cloud container services and machines still to come.

## Decision Drivers

- **No click-ops.** Every machine is created and configured from code in this repository.
- **D-0008 rule 3.** Root folders are named for their job. A vendor product is never a root folder name, apart from the stated `kubernetes/` exception.
- **Replaceable** (REQ-0011). Swapping a vendor product should replace one folder, not rename a root folder.
- **Public repository** (CLAUDE.md rule 4). Single machine addresses and hostnames never go here. STD-0002 (proposed) holds the rule for addresses.

## Considered Options

1. **`hosts/` holds every machine below Kubernetes, wherever it runs, with one subfolder per vendor product** (`hosts/terraform/`, `hosts/ansible/`).
2. **One root folder per vendor product** (`terraform/`, `ansible/`). This is common in public repositories (batch RB-0036; not counted).
3. **A root `infra/` folder**, as Jon's earlier Hill90 repository used (batch RB-0033).

## Decision Outcome

Chosen option: **1**. Jon said yes to keeping `hosts/` on 2026-10-20 at 03:25 UTC. In the same message he said Terraform modules will be kept in another repository. He said yes to `terraform/` as a vendor-product subfolder name on 2026-10-19 at 03:51 UTC, in his review of the organize-repository skill changes (item 9). Jon accepted this record under D-0001 on 2026-10-22 at 07:15 UTC.

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

- **Evidence:** no research batch of its own. Its naming rules come from the repository layout batch RB-0036, which D-0008 rests on: [../research/0008-name-the-prd-specs-and-root-folders.md](../research/0008-name-the-prd-specs-and-root-folders.md), finding 2.
- Related records: D-0001, D-0008. Related standard: STD-0002 (proposed).

## Corrections

- **2026-10-23** (requirement IDs respelled under D-0014): 1 requirement ID renamed, `SR11` to `REQ-0011`. Before: `SR11`; after: `REQ-0011`, and the same for each pair listed. Reason: D-0014 retires the `SR` spelling and its rule 5 renames live references in place; no decision changes. Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23).
- **2026-10-23** (research batch IDs under D-0015): 2 research batch citations renamed: `RL4` to `RB-0036`; `RL2` to `RB-0033`. Reason: D-0015 numbers research batches `RB-NNNN`, and its rule 5 renames live references in place; no decision changes. Approval: the owner, 2026-10-23T04:59:42Z (approval-ref cmsg_01X43rfNYp4H1dL1V2dkfkwN7qM5qKKp8HDEfuF6EYoQkC), naming PR #27 and head 8d63c29; approved commit 8d63c29543a8adccdebb9704146d067b238e1c54. Check: the drafting agent read the message at 2026-10-23T04:59Z and confirmed it names that PR and head.
- **2026-10-23** (owner's words and approvals recorded in neutral form under D-0016). Reason: D-0016 rules 5 to 7 and its "What happens to the existing records"; no decision changes. Where the text removed is the owner's words, this entry names where it was and a commit that holds it (7915625) instead of copying it (D-0016 rule 7).
  1. `accepted-evidence` rewritten once into D-0016 rule 6 fields with D-0006 step 7's fixed mapping, as amended by D-0016: `timestamp` to `approved-at`, `message-id` to `approval-ref`, `quote-check` to `check`; `approved-by: owner` and `approval-names` added; `quote` removed (its text is in `accepted-evidence.quote` at commit 7915625). No value changes.
  2. Context and Problem Statement, second paragraph: the quote of Jon's 03:03 UTC message (at commit 7915625) replaced by a neutral summary. After: "On 2026-10-20 at 03:03 UTC Jon said that nothing on the Proxmox hypervisor should be set up by hand, and asked where its code should go in central-hub, along with VPS machines, cloud VMs, cloud container services and machines still to come."
  3. Considered Options, option 2. Before: "(Research repo, RB-0036 `R1-design-independent.md` line 122; not counted)" After: "(batch RB-0036; not counted)" Reason: the old pointer is private.
  4. Considered Options, option 3. Before: "(Research repo, RB-0033 `S3-jon-repos.md`)" After: "(batch RB-0033)" Reason: the old pointer is private.
  5. Decision Outcome, first paragraph: the quote of Jon's 03:25 UTC answer (at commit 7915625) removed. After: "Jon said yes to keeping `hosts/` on 2026-10-20 at 03:25 UTC."
  6. More Information, first bullet. Before: "Research behind it: Research repo, `labs/central-hub/repo-layout/rl4/` (`RULES-v4.md` N2, N5, F1; `SYNTHESIS.md`, "Where machine and VM code goes")." After: "**Evidence:** no research batch of its own. Its naming rules come from the repository layout batch RB-0036, which D-0008 rests on: [../research/0008-name-the-prd-specs-and-root-folders.md](../research/0008-name-the-prd-specs-and-root-folders.md), finding 2." Reason: the old pointer is private; D-0016 rule 2.
  7. The 2026-10-23 requirement-ID entry above: its approval, which quoted the approval message (at commit 7915625), rewritten as D-0016 rule 6 facts. After: "Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23)." No value changes.

  Approval: the owner, 2026-10-23T06:07:52Z (approval-ref cmsg_01X43rfNYp4H1dL1V2dkfkwNAnCf1qE6ULcTZw9foG87Mc), naming PR #32 and head f994dac; approved commit f994dacd8fb34b10e550664797bf61d12af773a6. Check: the drafting agent read the message at 2026-10-23T06:07Z and confirmed it names that PR and head.
