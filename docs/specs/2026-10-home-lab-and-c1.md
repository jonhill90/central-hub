---
title: Build the home lab from code and the first cluster c1
status: proposed
date: 2026-10-26
system: 8
accepted-evidence:
done-evidence:
supersedes: []
superseded-by:
---

# Build the home lab from code and the first cluster c1

## What and why

The home lab today was set up by hand. This change puts it under code in `hosts/` (D-0011) and builds the first Kubernetes cluster, `c1`, on it. It serves PRD goal 1 (run upstream Kubernetes, starting with one home-lab cluster on Proxmox) and goal 6 (everything controllable from this repo). It is the first change that spans several sessions and crosses systems, so it gets a spec (D-0007 rule 2).

Agents build and test it; the owner validates the runbooks later by hand (decision log, 2026-10-26). Everything here is version 0.1 and is expected to change after the owner's review.

Parts, in order:

1. Proxmox access for automation: a Terraform-only user in the built-in `pve` realm, in a group, with a role and a limited, expiring API token. `root@pam` stays the break-glass account.
2. One Proxmox resource pool per workload, named by job: `firewall`, `remote-access`, `k8s`.
3. `tofu apply` for the lab network (SDN zone and VNets per STD-0002), the firewall VM and the remote-access container, importing what exists.
4. Ansible for the Proxmox host and the firewall.
5. Node VMs for `c1` in the `k8s` pool, named per STD-0001.
6. The cluster API name `api.c1.prod.<zone>` (STD-0001 rule 4) resolves inside the lab.
7. `c1` built with kubeadm by `docs/runbooks/build-kubeadm-cluster.md`, with pod and service ranges from STD-0002.

## Out of scope

- A pipeline that runs `tofu apply`. Nothing reads this repo until the Activation gate passes (AGENTS.md).
- Remote state. State stays as local files on the owner's machine for now.
- Ingress, certificates, GitOps engine, secrets backend, identity, observability, storage. Each is a later change.
- Bare-metal nodes. Proxmox is used for now; bare metal comes with more hardware.
- The VPS. It is not a node of `c1`.

## Acceptance criteria

### Automated

- [ ] `tofu plan` in each runnable folder under `hosts/terraform/home/`, run right after apply: "No changes."
- [ ] `ansible-playbook --check` for each playbook in `hosts/ansible/playbooks/`, run after the real run: `changed=0`.
- [ ] `kubectl get nodes`: every node `Ready`.
- [ ] `kubectl version`: server version matches the runbook's target version.
- [ ] `cilium status --wait`: all components OK.
- [ ] From a lab VM, the cluster API name resolves to the control-plane address.
- [ ] The docs check passes, and a search of the diff finds no real hostname, domain, single address, MAC address or token.

### Manual (what the owner checks)

- [ ] Every choice an agent made is listed with its options, and the owner can find it.
- [ ] The owner changes one agent choice by editing code and re-applying, and the second plan shows only that change.
- [ ] The owner reads the kubeadm runbook and can say why each step is there.

## Points to (read when)

- [D-0011](../decisions/0011-keep-machine-code-in-hosts.md): read when placing a file in `hosts/`.
- [STD-0001](../standards/0001-names.md): read when naming a machine, pool or service.
- [STD-0002](../standards/0002-ip-address-plan.md): read when giving anything an address or VLAN.
- [STD-0003](../standards/0003-version-choice.md): read when pinning a version.
- [Set up the Proxmox host](../runbooks/set-up-proxmox-host.md): read before step 1.
- [Build a kubeadm cluster](../runbooks/build-kubeadm-cluster.md): read before step 7.

## Decision log

- 2026-10-26: Resource pools, one per workload, named by job: `firewall`, `remote-access`, `k8s`; the network folder has no pool (owner's yes; STD-0001 names pools by job).
- 2026-10-26: STD-0001 covers containers and appliance VMs; new codes OS `op`, role `nw` (owner's yes; the STD-0001 edit is not made yet).
- 2026-10-26: One VLAN data file per place, read by both Terraform and Ansible (owner's yes); STD-0002 stays the rule and the docs check compares the two.
- 2026-10-26: Terraform's Proxmox account is `iac@pve`, group `iac`, role `IacOps`, token `apply`, limited and expiring; `root@pam` is break-glass only (owner's yes).
- 2026-10-26: An agent runs `tofu apply` on the owner's machine, to prove and measure it; the owner's learning focus is Kubernetes (owner's yes).
- 2026-10-26: c1 nodes sit on VNet `prod`, VLAN 10, as built (owner's yes).
- 2026-10-26: Lab DNS for the cluster API name is an OPNsense Unbound host override, one per name, until AdGuard Home replaces it (owner's yes).
- 2026-10-26: Proxmox VM IDs in ranges by job: 100-199 network and appliances, 200-299 Kubernetes nodes, 9000+ templates (owner's yes).
- 2026-10-26: The Terraform token expires after 90 days; its secret is in a 0600 file on the owner's machine (owner's yes).
- 2026-10-26: c1 nodes have 2 vCPU, 4 GB memory and 40 GB disk each, with fixed addresses (owner's yes).
- 2026-10-26: The node template uses a pinned AlmaLinux 10 cloud image URL, not "latest" (owner's yes).
- 2026-10-26: Role `IacOps` keeps its own least-privilege list rather than built-in roles (owner's yes).
- 2026-10-26: Home-lab changes fold into the one kubeadm runbook, with a place note per step (owner's yes).
- 2026-10-26: Agent choices for the owner's review: VM ID ranges, node sizes, node VLAN (prod, VLAN 10), lab DNS tool for the API name, token expiry.
