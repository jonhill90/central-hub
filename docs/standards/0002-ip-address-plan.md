---
id: STD-0002
title: IP address plan
status: active
scope: every private IPv4 and IPv6 range used by the home lab, VPS providers, clouds and Kubernetes clusters
owner-system: 8 Platform
why: the owner said yes to the proposed pool `10.0.0.0/8`, one /16 per place, the lot numbers, the VPS counted as cloud, the home lot and the home VLANs on 2026-10-24 between 06:29 and 07:22 UTC; to keeping ranges in this repo and machine addresses out of it on 2026-10-22 at 04:47 UTC; and to the IPv6 option "plan now, switch on later" on 2026-10-22 at 06:13 UTC, in the project's IP address plan work
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
2. Each place gets one /16, a "lot". The 2nd number MUST be the lot. Lots go in binary steps: `10.1`, `10.2`, `10.4`, `10.8`, `10.16`, `10.32`, `10.64`, `10.128`.
3. A VPS is not its own kind of place. It counts as cloud.
4. At home the 3rd number MUST be the VLAN ID, in steps of 10. Kubernetes nodes have no VLAN of their own; each node sits in its environment's network.
5. A new place, lot or VLAN MUST be added to the tables below, with the owner's approval, before it is used.
6. A range in this plan MUST NOT overlap another range in this plan.

### IPv4 places

| Range | Place | Notes |
|---|---|---|
| `10.1.0.0/16` | home lab | |
| not chosen yet | Azure, AWS, Google Cloud, VPS providers | Each takes one lot from rule 2. |
| not chosen yet | Kubernetes pods and Services | The manual cluster runbook uses `10.244.0.0/16` for pods and `10.96.0.0/12` for Services for now. Neither falls in a lot. |

### Home lab VLANs

| VLAN | Range | Use |
|---|---|---|
| 10 | `10.1.10.0/24` | prod |
| 20 | `10.1.20.0/24` | QA and stage |
| 30 | `10.1.30.0/24` | dev |
| 50 | `10.1.50.0/24` | management |

House Wi-Fi, IoT and guest devices stay on the home router's own LAN, outside this plan for now.

A load-balancer reserve inside these networks is not chosen yet.

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

A new dev lab VM on VLAN 30 takes an address from `10.1.30.0/24`. The address itself is not written in this repository.

## Not covered here

- The load-balancer reserve, and which tool answers for its addresses. That waits for the ingress decision.
- Per-machine addresses and DHCP reservations. They live outside this public repository.
- Public addresses from providers.
