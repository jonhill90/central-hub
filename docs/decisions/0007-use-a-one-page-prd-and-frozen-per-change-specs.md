---
id: D-0007
title: Use a one-page PRD and frozen per-change specs as version 1 of Central Hub's requirement records
status: accepted
date: 2026-10-19
decision-makers: [owner]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001, D-0003]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-19T02:53:10Z
  approved-commit: 5a074271302bdfd7ad048432ce4790d38b40a470
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNTRAgZJF48qYp51Qbbdd9ns
  approval-names: "PR #12 and head 5a07427, in the message itself"
  check: the drafting agent read the message in the PRD and spec research thread at 2026-10-19T02:53Z, and the recorded wording matched it exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: PR #12 merged at 2026-10-19T02:53Z as 4f157f8, with this evidence commit on top of the approved commit
revisit-when: a second person must agree on scope; code lands in this repo; a study measures whether a project-level PRD helps people or agents; or merged specs are being read as current truth
---

# Use a one-page PRD and frozen per-change specs as version 1 of Central Hub's requirement records

## Context and Problem Statement

The project brief, written by the coordinator agent on 2026-10-06, asks for a PRD and specifications, and for maintained, indexed documentation that shows detail step by step to people and agents (Research repo, `coordinator/platform-startup/BRIEF.md`, line 5). The owner also asked that a spec point to the code rather than repeat it, so code is never updated in two places (Central Hub project, 2026-10-17 21:30 UTC). He said he has to pick something for version 1, knowing it will be replaced (2026-10-17 20:36 UTC).

Three drafts exist in the Research repo and none is accepted: a platform PRD, a documentation contract and a first-slice spec. This record decides which documents hold "what and why" and "what changes", and what happens to them after a merge.

## Decision Drivers

- **What the evidence shows.** Research batch RB-0057 ([evidence](../research/0007-use-a-one-page-prd-and-frozen-per-change-specs.md)) found:
  - 81.5% of spec files in public repos have one commit, so most specs behave as frozen records.
  - Measured gains come from short, curated context and from checks, not from longer spec documents.
  - No study shows that a project-level PRD helps people or agents.
- **The owner chose a PRD.** On 2026-10-19 the owner said yes to a decision card for a one-page PRD plus frozen per-change specs. The PRD is kept on that answer, not because the evidence requires it.
- **Point to the code.** IEEE 830-1998 says the same requirement "should not appear in more than one place". The modern sources agree.
- **Fit the accepted rules.** The fit was checked in RB-0057 (evidence finding 8):
  - The owner accepts work by a message naming the PR number and head SHA (AGENTS.md rule 1, D-0001).
  - Every document kind sits under `docs/`.
  - Labels are written with the file name (D-0003).
- **Replaceable** (REQ-0011).

## Considered Options

1. **Living spec:** one document per capability, kept current, with each change merged into it (Spec Kit "Living Spec", OpenSpec).
2. **Frozen spec per change, plus a one-page PRD:** one spec per change, frozen once the change is accepted (Python PEP 1, Kubernetes KEPs, Spec Kit "Flow-Forward").
3. **Throw-away plan:** a working file used while building, deleted afterwards (Pocock, agent plan modes).
4. **Tests are the spec:** acceptance criteria written as executable checks (Specification by Example).
5. **No separate document:** the PR or issue description holds the spec (GitLab, BMAD).

## Decision Outcome

Chosen option: **2**. The owner said yes to the proposed option on 2026-10-19 at 02:38 UTC, on a decision card that asked: "Use a one-page PRD plus frozen per-change specs in docs/specs/ as version 1?" That answer chose the option, and the owner accepted this record under D-0001 on 2026-10-19 at 02:53 UTC.

```mermaid
flowchart TB
  PRD["PRD: one page<br/>names its system first,<br/>goals, non-goals, success signals"] -- links --> REQ["Requirement rows (REQ)"]
  B["Branch for a change"] --> S["Spec file in docs/specs/<br/>status: proposed"]
  S --> J{"the owner accepts:<br/>PR number + head SHA"}
  J -- yes --> M["Merge records it<br/>spec status says it is history"]
  M --> D["Lasting decisions go to<br/>docs/decisions/"]
  S -. "points to, never copies" .-> C["Code and tests"]
```

*In words:* there is one short PRD. A change big enough to need it gets one spec file, written on the change's branch. The owner accepts the spec with his PR-and-SHA message, and the merge records that acceptance. After merge the spec is history, and its status field says so. Anything that has to last becomes a decision record. Specs point to code and tests and never copy them.

### Rules

1. **PRD.** One page.
   - It names its system first (system 8, Platform) and leads with a drawing.
   - It holds goals, non-goals and success signals, and links to the requirement rows.
   - It holds no "how".
   - It replaces the Research repo's platform PRD draft, so there is one PRD.
2. **When a spec is needed.** Only for work that spans several sessions or crosses systems. Smaller changes need only the PR description.
3. **Where specs live.** One file per change in `docs/specs/`, named `YYYY-MM-<slug>.md`. The folder has a generated index, as `docs/decisions/` does.
4. **What a spec holds.**
   - What and why.
   - Acceptance criteria, split into automated (commands) and manual (what the owner checks).
   - A decision log for choices made during the change.
   - Sketches of code that does not exist yet are allowed.
   - The agent that writes the code does not edit the acceptance criteria in the same step.
5. **Acceptance and freezing.**
   - The owner accepts a spec as he accepts a record: a message naming the PR number and head SHA.
   - The merge records the acceptance.
   - A spec carries a status field, and after merge its body is not edited.
   - Agents treat a merged spec as history, not as current truth.
6. **Pointing to code.**
   - Never copy existing code, requirement rows or decision records. Link to them instead.
   - The PRD points at `main`.
   - A merged spec uses commit-pinned links.
   - Every link says when to read it.
   - Links go one level deep.
7. **Layers.** There are at most two. The PRD and the root agent file are the top layer, and everything else is one link away.
8. **Labels** inside a spec or the PRD are written with the file name (D-0003). No new global ID family is added.

### Not decided here

Each of these is a later decision for the owner:
- which store holds one system's PRD and specs about another system;
- whether a decision record may be edited before it is implemented.

### Consequences

- Good: matches how specs behave in practice: most are written once and not touched again.
- Good: it fits D-0002 short-lived branches and the owner's PR-and-SHA acceptance.
- Good: code lives in one place, so nothing is updated twice.
- Bad: specs do not describe the current system. A reader must look at the code, the PRD and the decision records for that.
- Bad: the PRD rests on the owner's answer to the 2026-10-19 card, not on measured evidence. BMAD's guidance would skip it for a one-owner project.
- Neutral: the rules are prose until code lands. The evidence favours checks, so checks are the next step.

### Confirmation

- Each merged spec has a status field and an acceptance message naming its PR and head SHA.
- No spec or PRD contains a copy of existing code, requirement rows or decision records. A reviewing agent checks each spec PR for this.
- `docs/specs/` has a generated index once its first spec exists.

## Pros and Cons of the Options

### 1. Living spec
- Good: one place says how the system works now.
- Bad: in practice, 47.4% of OpenSpec's "living" capability specs have one commit.
- Bad: someone must merge every change back into the spec.

### 3. Throw-away plan
- Good: cheapest.
- Bad: the acceptance criteria have no lasting home.
- Bad: a plan pushed to a branch of this public repo is published even after it is deleted.

### 4. Tests are the spec
- Good: has the strongest evidence. Rules turned into checks got 88.3% compliance versus 67.0%.
- Bad: there is no code yet, so nothing runs the checks.

### 5. No separate document
- Good: least to maintain.
- Bad: the record sits outside git, which D-0001 rejected for decisions.
- Bad: the owner chose to keep a PRD.

## More Information

- **Evidence:** [../research/0007-use-a-one-page-prd-and-frozen-per-change-specs.md](../research/0007-use-a-one-page-prd-and-frozen-per-change-specs.md): batch RB-0057, with a recall check that found 194 of 220 known items, an independent check of 150 claims (140 supported, none false) and a check of the fit with the organization research.
- **Exit path:**
  - Delete the PRD; the requirement rows remain.
  - Stop writing specs; merged specs stay as history.
  - Nothing here adds a tool.
