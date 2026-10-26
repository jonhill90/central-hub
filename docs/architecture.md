# Architecture

How the parts fit today. This file is living: it changes with each PR that changes how the parts fit (D-0012). It holds no "why" (see `docs/decisions/`) and no steps (see `docs/runbooks/`).

Created with the first real files in `hosts/` (D-0012 rule 2). Status: home lab, version 0.1. It describes the code in `hosts/`; the build that applies it is the spec [Build the home lab from code and the first cluster c1](specs/2026-10-home-lab-and-c1.md).

```text
 owner's machine ── runs ──▶ OpenTofu (local state) ──▶ Proxmox API (token: iac@pve!apply)
        │                     Ansible ───────────────▶ Proxmox host, firewall VM
        │
        └── remote access ──▶ remote-access container (pool remote-access) ──┐
                                                                             ▼
 ┌──────────────────────── Proxmox host (one node, home) ─────────────────────────────┐
 │  SDN zone "lab", VNets per VLAN (STD-0002): 10 prod · 20 qa/stage · 30 dev · 50 mgmt │
 │                                                                                    │
 │  pool firewall       firewall VM (OPNsense): routes between VLANs, lab DNS          │
 │  pool remote-access  remote-access container: subnet router into the lab           │
 │  pool k8s            c1 node VMs: control plane + worker(s), VLAN 10               │
 │                        └─ Kubernetes (kubeadm), Cilium; pods 10.240.0.0/16,         │
 │                           services 10.96.0.0/16 (STD-0002)                          │
 └────────────────────────────────────────────────────────────────────────────────────┘
```

## Parts

| Part | Made by | Code | Replaceable by |
|---|---|---|---|
| Terraform account, role, token and pools | a script run once on the Proxmox host | `hosts/terraform/home/bootstrap/` | the same steps by hand (`docs/runbooks/set-up-proxmox-host.md`) |
| Lab network (SDN zone, VNets) | OpenTofu, bpg/proxmox | `hosts/terraform/home/network/` | any provider that manages Proxmox SDN; VLANs stay in one data file |
| Firewall VM | OpenTofu (VM), Ansible oxlorg.opnsense (config) | `hosts/terraform/home/firewall/`, `hosts/ansible/roles/` | another router appliance; addresses stay per STD-0002 |
| Remote-access container | OpenTofu | `hosts/terraform/home/remote-access/` | any subnet router |
| c1 node VMs | OpenTofu | `hosts/terraform/home/k8s/` | bare-metal nodes later |
| c1 cluster | kubeadm, by runbook | `docs/runbooks/build-kubeadm-cluster.md` | another distribution; upstream Kubernetes APIs stay |

## What reads what

- Terraform and Ansible both read the VLAN data file for this place (one file, two readers). It is the copy in code of STD-0002's Home VLANs table, and the docs check fails when they differ.
- Nothing reads this repo on its own. Every apply is run by hand until the Activation gate passes (AGENTS.md).
