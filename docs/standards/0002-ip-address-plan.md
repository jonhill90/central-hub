---
id: STD-0002
title: IP address plan
status: active
scope: every private IPv4 and IPv6 range used by the home lab, VPS providers, clouds and Kubernetes clusters
owner-system: 8 Platform
why: kept from the IP address plan work, where the owner said yes to the proposed pod range 10.244.0.0/16 on 2026-10-22 at 01:54 UTC, to layout A (2nd number = place) at 02:50 UTC, to keeping ranges in this repo and machine addresses out of it at 04:47 UTC, to the load-balancer reserve at 05:25 UTC, and to the IPv6 option "plan now, switch on later" at 06:13 UTC, in the project's IP address plan work
follows: [RFC 1918 private IPv4, RFC 6598 shared address space (avoided), RFC 4193 unique local IPv6, RFC 4291 IPv6 addressing (/64 per link), RFC 7381 enterprise IPv6 deployment, Azure IP planning guide (IPv6 subnets exactly /64), Kubernetes dual-stack]
check: none yet in this repo; an overlap check script exists outside it, and where scripts live here is not decided yet
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

## Rule

### IPv4 shape

1. Every private IPv4 range MUST come from `10.0.0.0/8`.
2. The 2nd number MUST be the place. Which number each place gets is not chosen yet; the letters H, V and A below stand for them.
3. The 3rd number MUST be the environment band: 10-19 dev, 20-29 QA, 30-39 prod, 90-99 shared. At home the 3rd number MUST also be the VLAN ID.
4. A new place, VLAN or environment band MUST be added to the tables below, with the owner's approval, before it is used.
5. When the place numbers are chosen, a range in this plan MUST NOT overlap another range in this plan.

### IPv4 places

| Range | Place | Notes |
|---|---|---|
| `10.96.0.0/12` | Kubernetes Services | Cluster 1 Services. |
| `10.H.0.0/16` | home lab | H not chosen yet. |
| `10.V.0.0/16` | VPS providers | V not chosen yet. For private ranges on the VPS (for example container networks). |
| `10.A.0.0/16` | Azure | A not chosen yet. A VNet is a /24 to /20 cut from it, never a /16. |
| not chosen yet | AWS, Google Cloud | Later. |
| `10.240.0.0/12` | Kubernetes pods, all clusters | Cluster 1 pods `10.244.0.0/16`. `10.245.0.0/16` kept free for a network plugin migration. |

### Home lab VLANs

| VLAN | Range | Use |
|---|---|---|
| 10 | `10.H.10.0/24` | dev: Kubernetes node VMs |
| 11 | `10.H.11.0/24` | dev: lab VMs |
| 30 | `10.H.30.0/24` | prod: Kubernetes node VMs |
| 90 | `10.H.90.0/24` | shared: management |
| 91 | `10.H.91.0/24` | shared: IoT and guest (after the hardware firewall) |

On each Kubernetes node VLAN, `.224/27` (`10.H.10.224/27`, `10.H.30.224/27`) is for load-balancer addresses. DHCP MUST NOT hand out addresses from it, so DHCP pools end before `.224`.

### Azure environments

| Range | Use |
|---|---|
| `10.A.10.0/24` | dev VNet |
| `10.A.20.0/24` | QA VNet |
| `10.A.30.0/24` | prod VNet |
| `10.A.92.0/22` | connectivity hub (shared) |

### Ranges that MUST NOT be used

| Range | Taken by |
|---|---|
| `100.64.0.0/10` | Tailscale addresses |
| `169.254.0.0/16` | link-local |
| `172.17.0.0/16` to `172.31.0.0/16` | container defaults; AKS rejects 172.30-31 |
| the home router's own LAN | kept in the private store (not chosen yet), not written here |
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

A new dev lab VM on VLAN 11 takes an address from `10.H.11.0/24` by DHCP, below `.224`. The address itself is not written in this repository.

## Not covered here

- Which tool answers for the load-balancer addresses. That waits for the ingress decision.
- Per-machine addresses and DHCP reservations. They live outside this public repository.
- Public addresses from providers.
