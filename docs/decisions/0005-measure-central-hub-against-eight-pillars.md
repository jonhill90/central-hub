---
id: D-0005
title: Measure all of Central Hub against six industry pillars plus two labelled Central Hub pillars
status: accepted
date: 2026-10-16
decision-makers: [jon]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-16T03:02:19Z
  approved-commit: ebc80192168bf3861b751f56ee48ceb9d323c5c8
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNWohWWHVMqtatyVxFJbMSKg
  approval-names: "PR #8 and head ebc8019 by context; it answers the agent's message (03:00:34Z) that named both"
  check: the drafting agent read the message in the Kubernetes thread at 2026-10-16T03:02Z, and the quote matches exactly. It answers the agent's message in the same thread (03:00:34Z), which named PR #8 and head ebc8019 and asked for "accept" naming both. The message itself names neither, so it relies on that context, as D-0003's and D-0004's acceptances did. An independent check by a reviewing agent is still to do.
  merged: not yet; the owner merges PR #8, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: a CNCF document defines its own pillar set; a pillar has no working check after the cluster runs; or two pillars keep producing the same findings
---

# Measure all of Central Hub against six industry pillars plus two labelled Central Hub pillars

## Context and Problem Statement

On 2026-10-15 (Central Hub project, Kubernetes thread) the owner asked for the homelab to be a leading example of Kubernetes reliability, high availability, resiliency, cost optimisation and the other Microsoft Well-Architected pillars, in a CNCF-based version of Central Hub's own. He scoped it to the whole of Central Hub, not to one cluster or one cloud service.

There is no CNCF well-architected framework. Each cloud vendor publishes its own, and they overlap. Central Hub also has goals that no published framework treats as a pillar, above all that every component can be swapped. This record decides which pillars Central Hub is measured against, and where the line sits between adopting a standard and adding our own.

Research: batch RB-0014 ([evidence](../research/0005-measure-central-hub-against-eight-pillars.md)), a 96-claim ledger with an independent review, and the proposal `central-hub/operating-model/PILLARS.md` in the project Library. The owner agreed the shape on 2026-10-15, where "B" was the proposal's name for what is option 1 below, on two conditions: the mapping between industry pillars and Central Hub pillars stays clear, and the framework is treated as replaceable like everything else.

## Decision Drivers

- **Use the industry's words.** Someone who knows Azure, AWS or Google Well-Architected should recognise every standard pillar by name.
- **Whole system.** The pillars apply to the cluster, agents, identity, knowledge, documentation, the repository and the decision process.
- **Replaceable** (REQ-0011 in the requirements register): this framework, too, must be easy to drop or swap.
- **Clear line.** Anything that is ours must be labelled as ours.

## Considered Options

1. **Six industry pillars adopted as-is, plus two labelled Central Hub pillars** (Replaceability, Understandability), with an agent perspective as a lens across them.
2. **Azure Well-Architected as-is**: five pillars.
3. **AWS or Google as-is**: six pillars, including Sustainability.
4. **A framework of our own**, with new names throughout.

## Decision Outcome

Chosen option: **1**, because it keeps every industry name and checklist and adds only what all of them leave out, with a label saying so.

```mermaid
flowchart TB
  subgraph A[A. Industry pillars, adopted as-is]
    P1[1 Reliability]
    P2[2 Security]
    P3[3 Operational Excellence<br/>incl. observability]
    P4[4 Cost Optimization]
    P5[5 Performance Efficiency]
    P6[6 Sustainability]
  end
  subgraph B[B. Central Hub pillars, labelled as ours]
    P7[7 Replaceability]
    P8[8 Understandability]
  end
  L[Agent perspective:<br/>a lens across all 8] -.-> A
  L -.-> B
  R[Working rules stay in the register:<br/>not pillars] ~~~ B
```

*In words:* Central Hub is measured against eight pillars in two labelled groups. An agent perspective applies across all eight. Rules about how agents and decisions work are not pillars.

**The line between standard and ours:**
1. **Adopt as-is.** A pillar shared by 4 or more of the 5 frameworks compared (Microsoft, AWS, Google, GitHub, HashiCorp) keeps its industry name and checklist. Security is in all 5. Reliability, cost and operations are in 4.
2. **Extend only where every standard is silent,** and label the result as a Central Hub pillar. None of the five makes replaceability or portability a pillar.
3. **One exception to rule 1:** Sustainability is a pillar in only 2 of the 5 (AWS and Google; Azure treats it as guidance across pillars). It is adopted with that difference noted.
4. Observability stays inside Operational Excellence, as in Azure (OE:07), so the mapping back to Azure Well-Architected is one to one.

**The pillars:**

| # | Pillar | Group | Origin | Register rows today |
|---|---|---|---|---|
| 1 | Reliability | industry | Azure, AWS, Google; HashiCorp "resilient systems" | REQ-0011, REQ-0022 |
| 2 | Security | industry | all five | REQ-0003, REQ-0019 |
| 3 | Operational Excellence | industry | Azure, AWS, Google; HashiCorp "automate" | REQ-0005, REQ-0010 |
| 4 | Cost Optimization | industry | Azure, AWS, Google; HashiCorp "optimize" | REQ-0023 |
| 5 | Performance Efficiency | industry | Azure, AWS, Google; HashiCorp "optimize" | REQ-0024 |
| 6 | Sustainability | industry | AWS and Google pillar; Azure guidance | REQ-0025 |
| 7 | Replaceability | Central Hub | ISO/IEC 25010:2023 "replaceability", under Flexibility | REQ-0002, REQ-0008, REQ-0011 |
| 8 | Understandability | Central Hub | none as a pillar; documentation is its main area | REQ-0001, REQ-0005, REQ-0006, REQ-0018, REQ-0020, REQ-0021 |

The register rows are in the Research repo's requirements register (`coordinator/system/REQUIREMENTS.md`).

**Agent perspective.** Google adds cross-pillar "perspectives" instead of new pillars. Central Hub's perspective asks how each pillar applies when the worker is an agent: one identity per agent (Security), model and token spend per agent (Cost), agent access that survives a rebuild (Reliability), attributed and explained agent actions (Understandability).

**Not pillars.** REQ-0007, REQ-0009, REQ-0012, REQ-0013 to REQ-0017, and REQ-0026 describe how agents and decisions work, not how the system is built. They stay as rules in the register. GitHub's "Governance" pillar is the nearest match, and those rules already cover it.

### Consequences

- Good: anyone who knows a cloud framework can read pillars 1 to 6 without learning new words.
- Good: every pillar now has at least one requirement in the register.
- Good: the two extensions are visible as ours, so they can be dropped without touching the rest.
- Bad: eight pillars is more than any single vendor framework, so reviews take longer.
- Bad: how each pillar is checked outside the cluster (agents, knowledge, repository) is not yet researched.
- Neutral: no peer-reviewed papers were searched in RB-0014.

### Confirmation

- Each pillar has at least one requirement in the register; the register check (`areas/documentation/research/requirements-register/check/` in the Research repo) catches broken rows.
- A future record proposing a component names how it affects each pillar.
- A reviewing agent checks that the pillar table here matches `PILLARS.md` in the Library.

## Pros and Cons of the Options

### 2. Azure Well-Architected as-is
- Good: the framework the owner already knows; no mapping needed.
- Bad: no Sustainability pillar, no replaceability, and it is written for Azure workloads.

### 3. AWS or Google as-is
- Good: six pillars, including Sustainability.
- Bad: still no replaceability or understandability, and both are written for their own clouds.

### 4. A framework of our own
- Good: fits Central Hub exactly.
- Bad: loses the industry names, so nothing maps back; against the "adopt where 4 or more agree" line.

## More Information

- **Evidence:** [../research/0005-measure-central-hub-against-eight-pillars.md](../research/0005-measure-central-hub-against-eight-pillars.md): batch RB-0014, a 96-row claim ledger and an independent review.
- **Exit path:** to move to plain Azure Well-Architected, drop or fold pillars 6 to 8. To move to plain AWS or Google Well-Architected, which both have Sustainability, drop or fold pillars 7 and 8 only. No content is lost, because every item already sits under a standard name or a labelled extension. A new record supersedes this one.
- **Sources** (fetched 2026-10-15):
  - Azure: https://learn.microsoft.com/en-us/azure/well-architected/pillars and the Operational Excellence checklist https://learn.microsoft.com/en-us/azure/well-architected/operational-excellence/checklist
  - AWS: https://docs.aws.amazon.com/wellarchitected/latest/framework/the-pillars-of-the-framework.html
  - Google: https://cloud.google.com/architecture/framework
  - GitHub: https://raw.githubusercontent.com/github/github-well-architected/main/docs/framework-overview.md
  - HashiCorp: https://developer.hashicorp.com/well-architected-framework/what-is
  - CNCF cloud native definition: https://raw.githubusercontent.com/cncf/toc/main/DEFINITION.md
  - ISO/IEC 25010 (secondary summary): https://quality.arc42.org/standards/iso-25010
