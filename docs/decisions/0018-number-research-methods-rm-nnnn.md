---
id: D-0018
title: Number research methods RM-NNNN
status: accepted
date: 2026-10-23
decision-makers: [owner]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001, D-0003, D-0006, D-0016]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-23T05:23:48Z
  approved-commit: b0925cfa06a2b2c80860328d9bdac47967fb0684
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNQzUuygf7ZccWtDTPe47K57
  approval-names: "PR #30 and head b0925cf"
  check: the drafting agent read the message in the project thread at 2026-10-23T05:23Z; it names PR jonhill90/central-hub#30 and head b0925cf itself. An independent check by a reviewing agent is still to do.
  merged: PR #30 merged at 2026-10-23T05:25Z as 381e1f2, with this evidence commit on top of the approved commit
revisit-when: the Activation gate passes; the methods catalogue moves into a tool with its own numbering; or the research gate stops citing methods by ID
---

# Number research methods RM-NNNN

## Context and Problem Statement

Research specs, ledgers and checks name the methods they use by an ID from the project's research methods catalogue, for example `RM-0033` for an independent check. The catalogue holds 122 methods, and 40 more are proposed. An agent made the first ID scheme, and the owner was never asked about it.

Research batch RB-0075 (evidence: [../research/0018-number-research-methods-rm-nnnn.md](../research/0018-number-research-methods-rm-nnnn.md)) found:

- The build scripts gave a method its number from its place in the list, so rebuilding or re-sorting the list would renumber methods.
- The scripts read the catalogue from a copy on one machine, not from the Research repo.
- Every method number checked meant one method and nothing else, so the IDs could be changed by script.
- The agent-made IDs had a different shape from `D-0007`, `REQ-0022` and `RB-0075`.

On 2026-10-23 at 05:18 UTC the owner chose `RM-0001` style, written the same way in every live file, on a decision card that also offered keeping the agent-made shape with only the numbering fixed, or leaving it as it is. Earlier that day the owner said that the cost of keeping an agent-made scheme is not a reason to keep it in a greenfield system (D-0014).

## Decision Drivers

- **One shape for every cited ID:** `D-0007`, `REQ-0022`, `STD-0001`, `RB-0075`.
- **A number stays with its method:** the published catalogues read, such as MITRE ATT&CK, mark retired entries and point to their replacement instead of deleting them.
- **Greenfield:** the IDs have no users outside the project. central-hub cites none.
- **Replaceable** (REQ-0011).

## Considered Options

1. **`RM-NNNN`, with each number stored in the catalogue.**
2. **Keep the agent-made shape, store the numbers and register it as it is.** It fixes the numbering for little cost, but keeps a different shape.
3. **Leave it as it is.** List-position numbering stays a risk.

## Decision Outcome

Chosen option: **1**, which the owner chose on 2026-10-23 at 05:18 UTC.

This adds the Research methods row to D-0003's registry, and D-0003 rule 6 says how a retired method is kept. `RM-` passes D-0003 rule 2's prefix check against `D-`, `REQ-`, `STD-` and `RB-`.

### The methods catalogue

- The catalogue stays one JSON file in the Research repo. Each method's `id` field is its number, in `RM-NNNN` form, and no script works it out from the list.
- A new method gets a number only after the owner says yes to adding it. RB-0055's 40 proposed methods have no number until then.
- The Research repo copy is the only source. Scripts that read another copy are changed to read this one.
- A check fails on a duplicate number, a number not in `RM-NNNN` form, or a cited ID with no catalogue row.
- The research gate checks the method IDs in every new SPEC. Its hook runs from a setup script that the owner pastes by hand, so a change to the gate goes to the owner as a new setup script.
- Project instructions that cite a method ID are drafted by the agent, approved by the owner and saved by the coordinator.

### Consequences

- Good: every cited ID has one shape, and a method's number can no longer change by accident.
- Good: retired methods stay visible with a pointer to their replacement.
- Bad: a change to the research gate waits until the owner pastes the new setup script.
- Neutral: no method's name, content or sources depend on its number.

### Confirmation

- The catalogue check passes: no duplicate numbers and every ID in `RM-NNNN` form.
- A new SPEC passes the research gate with `RM-NNNN` IDs.

## Pros and Cons of the Options

### 1. RM-NNNN, stored numbers

- Good: one shape for every ID, and numbers stored.
- Bad: the largest change, with a setup-script step.

### 2. Keep the agent-made shape, store the numbers

- Good: fixes the numbering for little cost, and needs no hook change.
- Bad: keeps a shape different from every other registered family.

### 3. Leave it

- Good: no work.
- Bad: list-position numbering can renumber methods.

## More Information

- **Evidence:** [../research/0018-number-research-methods-rm-nnnn.md](../research/0018-number-research-methods-rm-nnnn.md)
- Related records: D-0001, D-0003, D-0006, D-0014, D-0015, D-0016.
