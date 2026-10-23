---
record: D-0005
batch: RB-0014
researched: 2026-10-15
method: rapid review of five well-architected frameworks, CNCF and upstream Kubernetes sources, check tools and seven public cluster repositories; claim ledger of 96 rows; independent review
checks: the ledger holds 96 rows (78 sourced, 18 inferred, 0 from model knowledge, 0 measured); an independent review checked 63 rows against freshly fetched sources, with verdict "pass with fixes", and all 10 fixes were applied
---

# Evidence for D-0005: the eight pillars

This file summarises the research behind D-0005. It adds nothing that the research did not find. Each finding below traces to a row in the batch ledger.

## Question

Which quality pillars should Central Hub be measured against, given that CNCF has no well-architected framework of its own and each cloud vendor publishes one?

## Findings

1. **The five frameworks compared overlap but differ.** Azure Well-Architected has five pillars [1], AWS six [3], Google six with cross-pillar "perspectives" [4], GitHub five [5] and HashiCorp four [6].
2. **Most pillars are shared.** Security appears in all 5 frameworks. Reliability and cost appear in the 4 infrastructure frameworks (Azure, AWS, Google, HashiCorp), and operational excellence or automation also appears in 4 [1, 3, 4, 5, 6].
3. **Sustainability is split.** AWS and Google make sustainability a pillar [3, 4]. Azure treats it as guidance across the pillars that "strongly overlaps with the Cost Optimization pillar" [2] (seen only in a search excerpt).
4. **Azure keeps observability inside operations.** Its Operational Excellence checklist covers the monitoring stack at OE:07, while CNCF's definition names "observable" as a top-level quality [1, 7].
5. **CNCF has no framework, only a definition.** CNCF's cloud native definition v1.1 names five qualities: "secure, resilient, manageable, sustainable, and observable" [7]. Its TAG Operational Resilience also covers cost, performance, energy and reliability [8].
6. **No framework makes replaceability a pillar.** None of the five frameworks has portability, replaceability or swappability as a pillar (inferred from their pillar lists). ISO/IEC 25010:2023 lists replaceability under Flexibility (formerly Portability) [9], and the CNCF Platforms White Paper names "portability across infrastructures" as a value platforms deliver [10].
7. **Public cluster repositories state no pillars.** None of the 7 repositories read states pillar-style quality goals. Their goals show up as features and tooling: GitOps in 6 of 7, Renovate in 5, backup and restore in 2, cost transparency in 2, policy as code in 1, and modularity or swappability in 2 [11].

## How the decision used it

(Written from the record, not from the batch.)

D-0005 adopts a pillar as-is where 4 or more of the 5 frameworks share it (findings 1 and 2), and adopts Sustainability with the split noted (finding 3). It keeps observability inside Operational Excellence, as Azure does (finding 4). It adds Replaceability as a labelled Central Hub pillar because no framework has one (finding 6). Understandability and the agent perspective come from the later proposal that widened the scope to all of Central Hub, not from this batch's ledger.

## Limits

- The batch covered the cluster only. The owner later widened the scope to all of Central Hub, and the shape with two Central Hub pillars was set in a proposal written after the batch.
- No peer-reviewed papers were searched.
- ISO/IEC 25010:2023 was read through a secondary summary, not the paid standard.
- Azure's sustainability position and one HashiCorp naming page were seen only in search excerpts.
- Nothing was measured: the VPS was out of scope.

## References

Relied on (the decision depends on these):

1. Microsoft, Azure Well-Architected, pillars and the Operational Excellence checklist. <https://learn.microsoft.com/en-us/azure/well-architected/pillars>, <https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/checklist>
2. Microsoft, Azure Well-Architected, sustainability overview (search excerpt only). <https://learn.microsoft.com/azure/well-architected/sustainability/overview>
3. AWS Well-Architected, "The pillars of the framework". <https://docs.aws.amazon.com/wellarchitected/latest/framework/the-pillars-of-the-framework.html>
4. Google Cloud Well-Architected Framework. <https://cloud.google.com/architecture/framework>
5. GitHub Well-Architected, framework overview. <https://raw.githubusercontent.com/github/github-well-architected/main/docs/framework-overview.md>
6. HashiCorp Well-Architected Framework. <https://developer.hashicorp.com/well-architected-framework/what-is>
7. CNCF, Cloud Native Definition v1.1. <https://raw.githubusercontent.com/cncf/toc/main/DEFINITION.md>
8. CNCF, Technical Advisory Groups. <https://contribute.cncf.io/community/tags/>
9. ISO/IEC 25010:2023 product quality model, secondary summary by arc42. <https://quality.arc42.org/standards/iso-25010>
10. CNCF Platforms White Paper. <https://tag-app-delivery.cncf.io/whitepapers/platforms/>
11. The 7 repositories read: onedr0p/home-ops, onedr0p/cluster-template, khuedoan/homelab, bjw-s-labs/home-ops, fluxcd/flux2-kustomize-helm-example, kubernetes/k8s.io and billimek/k8s-gitops, each at its README on its default branch.

Background (read, not relied on):

12. Kubernetes, "Production environment". <https://kubernetes.io/docs/setup/production-environment/>
13. CNCF TAG Observability whitepaper. <https://raw.githubusercontent.com/cncf/tag-observability/main/whitepaper.md>
14. OpenGitOps principles. <https://raw.githubusercontent.com/open-gitops/documents/main/PRINCIPLES.md>
15. FinOps Framework. <https://www.finops.org/framework/>
16. OpenCost. <https://opencost.io/docs/>

All fetched 2026-10-15, except where marked as a search excerpt.

## Working files

The 96-row ledger, the deviations log and the independent review are kept in the owner's private research archive as batch RB-0014. They are not needed to read this file.
