---
record: D-0047
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: Proxmox VE's copyright file and pricing page read; Incus's licence and support page read; central-hub searched for every file naming the piece; on 2026-11-14 at about 10:55 UTC, the pricing page and Proxmox's package repositories page opened again for the paid-repository weighing, the copyright file and Incus's sources re-read, and the reach re-counted at main 3d3bcf1
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch and the pages before the record is accepted"
---

# Evidence for D-0047: Proxmox VE as the hypervisor

This file summarises the research behind D-0047. It adds nothing the research and the pages listed below did not find.

## Question

Is Proxmox VE free and open source with nothing held back behind a paywall, what does a subscription buy, and what free alternative exists?

## Findings

1. **Licence.** Proxmox VE is AGPL-3.0-or-later, per pve-manager's `debian/copyright` ("License: AGPL-3+") [1] (measured).
2. **Paid plans.** The pricing page answers "Are Proxmox VE features limited by subscription level?" with "No. High availability, live migration, clustering, backup, software-defined storage, networking, and all other Proxmox VE features are available at every level." Plans differ by support. The cheapest plan "includes access to the Enterprise Repository but not ticket support". The top plan also lists offline updates and Proxmox Datacenter Manager, which the lab does not use [2] (sourced).
3. **The two repositories.** The enterprise repository "contains the most stable packages and is suitable for production use" and needs a subscription key. The no-subscription repository "can be used for testing and non-production use", and "these packages are not always as heavily tested and validated" [3] (sourced).
4. **Reach.** At main 3d3bcf1, 169 files in 88 `hosts/` folders, 29 runbooks and 16 records from D-0002 to D-0045 name Proxmox [4] (measured, 2026-11-14).
5. **Alternative.** Incus is Apache-2.0 [5] (measured). The Incus docs say "Commercial support is currently available from Zabbly for users of their Debian or Ubuntu packages" and name no paid-only feature [6] (sourced). Zabbly's own pricing page was not checked.
6. **The standard.** STD-0006 rule 2, accepted by the owner at 06:30:41 UTC on 2026-11-14, allows "selling support, hosting, training or tested builds of the same code", and its register lists Proxmox VE as a pass [7] (measured).

## How the decision used it

(Written from the record, not from the batch.)

Finding 1 sets rule 1. Findings 2, 3 and 6 are the weighing of the paid repository and rule 3. Finding 4 is the context. Finding 5 is option 2 and the exit path. The sign-in notice comes from the set-up runbook.

## Limits

- No feature or fit comparison with Incus was made.
- Whether a paid channel of more-tested updates is a paywall under the owner's words of 04:44:57 UTC is a reading, not a finding; the record says so.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. pve-manager `debian/copyright`. <https://git.proxmox.com/?p=pve-manager.git;a=blob_plain;f=debian/copyright;hb=HEAD>
2. Proxmox, "Proxmox VE pricing". <https://www.proxmox.com/en/products/proxmox-virtual-environment/pricing>
3. Proxmox VE wiki, "Package Repositories". <https://pve.proxmox.com/wiki/Package_Repositories>
4. Repository search of central-hub at 3d3bcf1 (this repository).
5. Incus COPYING. <https://raw.githubusercontent.com/lxc/incus/main/COPYING>
6. Incus, "Support". <https://linuxcontainers.org/incus/docs/main/support/>
7. STD-0006 and `docs/standards/components.yaml` in this repository.

The batch is RB-0208; its working files are private.
