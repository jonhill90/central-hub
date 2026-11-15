---
record: D-0050
batch: RB-0208 (FOSS check of every central-hub piece)
researched: 2026-11-14
method: Kubernetes and Talos licence files read from their repositories; Omni's licence measured; central-hub searched for every file naming kubeadm; on 2026-11-14 at about 11:10 UTC, the Kubernetes, Kubespray, Talos and Omni licence files and Sidero's pricing page read again, and the reach re-counted at main c275db4
checks: "None yet. RB-0208 had no independent check and no recall check; a reviewing agent checks every line here against the batch and the pages"
---

# Evidence for D-0050: kubeadm for c1

This file summarises the research behind D-0050. It adds nothing the research and the pages listed below did not find.

## Question

Is the Kubernetes installer the lab uses free with nothing held back behind a paywall, and what about the alternatives?

## Findings

1. **Kubernetes** (kubeadm is part of it) is Apache-2.0 [1] (measured). The FOSS register lists it as a pass: "a CNCF graduated project, vendors sell their own distributions" [6] (measured).
2. **Kubespray** is Apache-2.0 [5] (measured).
3. **Talos** is MPL-2.0 [2] (measured). Sidero's Omni is under the Business Source License [3] (measured), and no file in `hosts/` names Omni [7] (measured).
4. **Sidero's pricing page** lists the Community Edition as "Talos Linux, free and open source (MPL-2.0)", and "Talos Enterprise Linux — compliance, support, and Omni fleet management on the same open-source OS". Every paid plan includes Omni, CVE SLAs and "FIPS 140-3 compliant builds" [4] (sourced).
5. **Reach.** At main c275db4, 21 files in `hosts/` and 11 runbooks name kubeadm, and so do records D-0017, D-0021, D-0022, D-0023 and D-0024 [7] (measured, 2026-11-14).

## How the decision used it

(Written from the record, not from the batch.)

Finding 1 sets rule 1. Finding 2 is option 2. Findings 3 and 4 are option 3 and rule 3. Finding 5 is the context.

## Limits

- No installer was compared on fit.

## References

Relied on (the decision depends on these), fetched 2026-11-14:

1. Kubernetes LICENSE. <https://raw.githubusercontent.com/kubernetes/kubernetes/master/LICENSE>
2. Talos LICENSE. <https://raw.githubusercontent.com/siderolabs/talos/main/LICENSE>
3. Omni LICENSE. <https://raw.githubusercontent.com/siderolabs/omni/main/LICENSE>
4. Sidero Labs, "Pricing". <https://www.siderolabs.com/pricing/>
5. Kubespray LICENSE. <https://raw.githubusercontent.com/kubernetes-sigs/kubespray/master/LICENSE>
6. `docs/standards/components.yaml` in this repository, row `Kubernetes`.
7. Repository search of central-hub at c275db4 (this repository).

The batch is RB-0208; its working files are private.
