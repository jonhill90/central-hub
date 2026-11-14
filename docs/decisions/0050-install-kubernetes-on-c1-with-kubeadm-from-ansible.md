---
id: D-0050
title: Install Kubernetes on c1 with upstream kubeadm, driven by the lab's own Ansible roles
status: proposed
date: 2026-11-14
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: []
supersedes: []
superseded-by:
revisit-when: the owner moves c1 to an immutable OS such as Talos; the Talos rehearsal cluster passes the same confirmation as c1; kubeadm stops supporting the Kubernetes version c1 needs; the owner wants to try Kubespray; or a second cluster is built
---

# Install Kubernetes on c1 with upstream kubeadm, driven by the lab's own Ansible roles

## Context and Problem Statement

c1 is a kubeadm cluster on AlmaLinux VMs. The lab's own Ansible roles build and upgrade it (`k8s_node`, `k8s_control_plane`, `k8s_worker`, `playbooks/k8s-upgrade.yml`), following the runbooks [build-kubeadm-cluster.md](../runbooks/build-kubeadm-cluster.md) and [build-c1-with-ansible.md](../runbooks/build-c1-with-ansible.md). At main c275db4, 21 files in `hosts/` and 11 runbooks name kubeadm, and records D-0017, D-0021, D-0022, D-0023 and D-0024 build on it. No record chose it.

The owner's words this rests on:

- 2026-10-19 at 00:26 UTC: he needs to be able to do what the CKA exam covers, so there is a runbook for that, the lab will also use Ansible, and at some point it will probably use an immutable OS such as Talos. He also said it would be good to try the Kubespray way.
- 2026-10-26 at 04:15 UTC (cmsg_01X43rfNYp4H1dL1V2dkfkwN3q914dMTeQzubJRvjgprBy): no record is needed for installing kubeadm by hand, which he would do only to learn the process.
- 2026-11-12 at 15:01 UTC: the role defaults hold the version the cluster runs, and an upgrade starts with a pull request that bumps them (agent pick 33 in `hosts/AGENT-PICKS.md`, which records his answer).

This record is about the installer the lab's code uses, which the audit of 2026-11-14 found in no record, with its licence and its way out.

## Decision Drivers

- **What the CKA exam covers** (the owner, 2026-10-19).
- **Everything in code** (the owner, 2026-10-27).
- **FOSS with nothing held back behind a paywall** (REQ-0032; the owner, 2026-11-14; STD-0006 rule 2).
- **Replaceable** (CLAUDE.md rule 6), with Talos named as the later path (the owner, 2026-10-19).

## Considered Options

1. **Upstream kubeadm, from the lab's own Ansible roles.**
2. **Kubespray.**
3. **Talos Linux.**

## Decision Outcome

Proposed: **option 1**, because it is what runs and it follows the owner's order: the exam's steps first, in Ansible. Option 3 is the owner's named later path, and a rehearsal folder exists (`hosts/terraform/home/k8s-talos/`); moving to it is its own record (rule 3). Option 2 was not compared on fit.

Diagram: not applicable. One installer for one cluster; the node layout is in STD-0002 and the home-lab spec.

### Rules

1. **Licence.** Kubernetes and kubeadm, Apache-2.0, from the upstream package repositories only. The FOSS register lists Kubernetes as a pass: a CNCF project with no paid edition of its own.
2. **Versions** follow STD-0003 and agent pick 33. The roles' defaults are the running version, and an upgrade is a pull request that bumps them by at most one minor version.
3. **Talos, if it comes.** A move to Talos is its own record, which weighs Sidero's paid Talos Enterprise Linux under STD-0006 when it is made.

### Consequences

- Good: no change; the steps match what the owner studies.
- Bad: the lab maintains its own install and upgrade roles.

### Confirmation

- c1's control plane reports a kubeadm-made cluster at the version in the role defaults.

### Exit path

Workloads are in Argo CD (D-0023) and data is backed up off the box (D-0033). A cluster built another way (Talos, or another installer) takes the same apps by pointing Argo CD at it and restoring the backups.

## Pros and Cons of the Options

### Option 1: kubeadm from own Ansible roles

- Good: upstream; Apache-2.0; matches the exam.
- Bad: own roles to maintain.

### Option 2: Kubespray

- Good: a maintained Ansible installer, Apache-2.0; the owner named it as worth trying.
- Bad: not compared on fit; it would hide steps the exam asks for.

### Option 3: Talos

- Good: MPL-2.0; immutable; managed by API.
- Bad: a different way of working from the exam. Sidero's paid edition adds FIPS 140-3 compliant builds, CVE SLAs and Omni, and Omni is under the Business Source License.

## More Information

- Evidence: [`docs/evidence/0050-install-kubernetes-on-c1-with-kubeadm-from-ansible.md`](../evidence/0050-install-kubernetes-on-c1-with-kubeadm-from-ansible.md).
- Related: STD-0003, STD-0006 and its register (`docs/standards/components.yaml`), D-0023, D-0033.
