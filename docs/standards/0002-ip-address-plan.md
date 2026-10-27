---
id: STD-0002
title: IP address plan
status: active
scope: every private IPv4 and IPv6 range used by the home lab, VPS providers, clouds and Kubernetes clusters
owner-system: 8 Platform
why: the owner said yes to the proposed pool `10.0.0.0/8`, one /16 prefix per site or region, the home prefix and the home VLANs on 2026-10-24 between 06:29 and 07:22 UTC; to one /12 container prefix per kind of place on 2026-10-24 at 20:00 UTC; to the Kubernetes pod and Service ranges at 20:05 and 20:09 UTC; to the load-balancer addresses at 23:32 and 23:38 UTC; to a home-only first cluster on 2026-10-25 at 00:22 UTC; and to the ranges never used on 2026-10-25 at 00:29 UTC, in the project's IP address plan work. Also to keeping ranges in this repo and machine addresses out of it on 2026-10-22 at 04:47 UTC, and to the IPv6 option "plan now, switch on later" on 2026-10-22 at 06:13 UTC
follows: [RFC 1918 private IPv4, RFC 4632 CIDR (bit-aligned prefixes), RFC 6598 shared address space (avoided), RFC 4193 unique local IPv6, RFC 4291 IPv6 addressing (/64 per link), RFC 7381 enterprise IPv6 deployment, IEEE 802.1Q VLAN IDs, NetBox IPAM terms (aggregate, prefix, container prefix), Azure IP planning guide, kubeadm init, Kubernetes dual-stack]
check: the home VLAN table is checked against its copy in code by `.github/docs-check/check_vlans.py`, run with the docs check on every PR; the overlap check script exists outside this repo
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-22T07:12:48Z
  approved-commit: 5196b18f87c1b6a209291e62114fd5479833ade1
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNV1uvM92X9ekDHTkxTf1hLf
  approval-names: "PR #17 and head 5196b18, in the message itself"
  check: the drafting agent read the message in the IP address plan thread at 2026-10-22T07:12Z, and the recorded wording matched it exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: PR #17, commit e87667b
---

# STD-0002: IP address plan

The key words "MUST", "MUST NOT", "SHOULD" and "MAY" in this document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174) when, and only when, they appear in all capitals.

## Words

- **Aggregate:** the top block, `10.0.0.0/8`.
- **Prefix:** any block inside it.
- **Container prefix:** a prefix that holds smaller prefixes.

These are NetBox's terms; RFC 4632 also uses "prefix".

## Rule

### IPv4 shape

1. Every private IPv4 range MUST come from `10.0.0.0/8`.
2. Each kind of place gets one /12 container prefix, and each site or region gets one /16 prefix inside it. Every prefix MUST start on a bit boundary (RFC 4632), so each kind of place is one route.
3. Inside a container prefix, sites or regions take the next /16 in order.
4. A VPS is not its own kind of place. It has no prefix of its own.
5. At home the 3rd number MUST be the VLAN ID, in steps of 10. Kubernetes nodes have no VLAN of their own; each node sits in its environment's network.
6. Kubernetes pods, Services and BGP load-balancer addresses each get one /12 container prefix for all clusters, and one /16 per cluster inside it, in order.
7. A new place, prefix or VLAN MUST be added to the tables below, with the owner's approval, before it is used.
8. A range in this plan MUST NOT overlap another range in this plan.

### Container prefixes (/12)

| Range | Kind of place | Prefixes inside (/16) |
|---|---|---|
| `10.0.0.0/12` | on-prem | home `10.1.0.0/16`; `10.0.0.0/16` left empty for now |
| `10.16.0.0/12` | Azure | East US 2 `10.16.0.0/16`, Central US `10.17.0.0/16` |
| `10.32.0.0/12` | AWS | regions not chosen yet |
| `10.48.0.0/12` | Google Cloud | regions not chosen yet |
| `10.96.0.0/12` | Kubernetes Services | cluster 1 `10.96.0.0/16`, cluster 2 `10.97.0.0/16` |
| `10.224.0.0/12` | Kubernetes load-balancer addresses, BGP mode | cluster 1 `10.224.0.0/16`, cluster 2 `10.225.0.0/16` |
| `10.240.0.0/12` | Kubernetes pods | cluster 1 `10.240.0.0/16`, cluster 2 `10.241.0.0/16` |

kubeadm MUST be given `--service-cidr` and the CNI its pod range from this table, because their defaults are wider.

### Home VLANs

| VLAN | Range | Use | Load-balancer addresses (kept out of DHCP) |
|---|---|---|---|
| 10 | `10.1.10.0/24` | prod | `10.1.10.224/27` |
| 20 | `10.1.20.0/24` | QA and stage | `10.1.20.224/27` |
| 30 | `10.1.30.0/24` | dev | `10.1.30.224/27` |
| 50 | `10.1.50.0/24` | management | none |

The copy in code of this table is `hosts/ansible/inventories/home/group_vars/all/vlans.yml` (list `lab_vlans`), which Terraform and Ansible both read. This table is the rule. The docs check (`.github/docs-check/check_vlans.py`) fails when the file differs from it in a VLAN ID, use or prefix, so a VLAN change edits both in one PR.

The load-balancer addresses work in ARP or BGP mode; the mode is chosen with the ingress decision.

House Wi-Fi, IoT and guest devices stay on the home router's own LAN, outside this plan for now. When a hardware firewall replaces the lab router, home keeps `10.1.0.0/16` and these VLANs.

### First cluster

The first cluster is home only. Its nodes use their own VLAN addresses, not tailnet addresses. The VPS is not a worker for now.

### Ranges that MUST NOT be used

| Range | Taken by |
|---|---|
| `100.64.0.0/10` | mesh VPN addresses (Tailscale, Headscale, NetBird) |
| `169.254.0.0/16` | link-local |
| `172.17.0.0/16` to `172.31.0.0/16` | container defaults; AKS rejects 172.30-31 |
| the home router's own LAN | kept in the private store, not written here |
| `192.0.2.0/24`, `198.18.0.0/15` | documentation and benchmarking |

A product whose default range lands inside this plan (for example the AKS Service default `10.0.0.0/16`, the k3s defaults `10.42.0.0/16` and `10.43.0.0/16`, or the Cilium default cluster pool `10.0.0.0/8`) MUST be set to a range from this plan when it is installed.

### IPv6 (written down, switched on nowhere)

1. The unique local prefix is `fd21:4249:e0b0::/48`. It was generated once with a random 40-bit Global ID (RFC 4193), so it is clear of Tailscale's `fd7a:115c:a1e0::/48` and the AKS default `fd12:3456:789a::/48`.
2. Each VLAN gets one /64, whose 4th group reads like the VLAN number: VLAN 10 is `fd21:4249:e0b0:10::/64`, VLAN 30 is `fd21:4249:e0b0:30::/64`. That group is really hex (`10` is 16), and it MUST NOT be converted.
3. Kubernetes, for all clusters, gets `fd21:4249:e0b0:fa00::/56`, which no VLAN number reaches. A cluster's IPv6 Service range SHOULD be /108 or smaller.
4. IPv6 MUST NOT be switched on anywhere until the owner approves it. Host firewall rules MUST still cover IPv6 now, because hosts have it on by default.
5. Before a cluster gets IPv6, its pod MTU MUST be at least 1280 (RFC 8200).

### Machine addresses

This repository is public. A single machine's address MUST NOT be written here. It is a blank, filled in from GitHub secrets or the cluster's secret store at apply time. Ranges MAY be written here.

## Example that passes

A new prod Kubernetes node on VLAN 10 takes an address from `10.1.10.0/24` below `.224`. Its pods get addresses from `10.240.0.0/16`. The node's own address is not written in this repository.

## Not covered here

- Region prefixes inside AWS and Google Cloud, until they are used.
- The load-balancer mode (ARP or BGP), chosen with ingress.
- Which VLAN house devices get once a hardware firewall is in place, and whether `10.0.0.0/16` stays empty.
- Whether, and how, the VPS joins a cluster later.
- Per-machine addresses and DHCP reservations. They live outside this public repository.
- Public addresses from providers.
