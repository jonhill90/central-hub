---
record: D-0027
batch: "RB-0089 (the batch behind D-0023), plus a read-only check of c1 on 2026-11-08"
researched: 2026-11-08
method: a read-only inventory of c1 and its Proxmox host, run from the owner's Mac on 2026-11-08 at about 07:15 UTC; a reading of AGENTS.md, D-0023 and the backlog items for the gate (BL-0021, BL-0023)
checks: no independent check yet
---

# Evidence for D-0027: let c1 read central-hub before the Activation gate

This file summarises what the record rests on, and it adds nothing beyond that.

## Question

May the lab cluster c1 read central-hub through Argo CD before all 7 Activation gate checks pass?

## Findings

1. **Argo CD manages nothing on c1.** It runs v3.5.5 with 0 Applications, only the `default` AppProject, and no repository in `argocd-cm` (measured, 2026-11-08).
2. **Ansible put everything on c1.** There are seven Helm releases (cilium, metrics-server, cert-manager, external-secrets, kube-prometheus-stack, loki, alloy), plus plain manifests for Argo CD, Keycloak, the Local Path Provisioner and Jellyfin (measured, 2026-11-08).
3. **c1 holds no data that can't be rebuilt.** Jellyfin's setup wizard has not run (`StartupWizardCompleted: false`), and the owner called the lab "greenfield not in use" on 2026-10-26 at 06:30 UTC (measured, and sourced from the project chat).
4. **The gate's open item.** D-0023 lists "whether c1 may read central-hub before the Activation gate passes" under "Not decided here" (sourced, D-0023). Backlog item BL-0023 was parked on 2026-10-29 "until Jon decides to turn Argo CD on" (sourced, Research task BL-0023).
5. **The owner's answer.** On 2026-11-08 at 07:16 UTC the owner chose "Yes, for c1 only" on the card "Let c1 read central-hub through Argo CD before the Activation gate passes?" (sourced, project thread).

## How the decision used it

Findings 1 to 3 show what the exception risks: a greenfield cluster whose components can all be put back by Ansible. Finding 4 shows the question was left open on purpose, and finding 5 is the answer. The compensating controls in the record come from AGENTS.md rule 2 and D-0023 rule 6.
