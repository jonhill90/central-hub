---
id: D-0018
title: Spell research method IDs RM-NNNN, store each method's number, and rename the old IDs everywhere
status: accepted
date: 2026-10-23
decision-makers: [jon]
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
  merged: not yet; the owner merges PR #30, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: the Activation gate passes; the methods catalogue moves into a tool with its own numbering; or the research gate stops citing methods by ID
---

# Spell research method IDs RM-NNNN, store each method's number, and rename the old IDs everywhere

## Context and Problem Statement

Research specs, ledgers and checks name the methods they use by an ID from the project's research methods catalogue, for example `RM33` for an independent check. The catalogue holds 122 methods, `RM01` to `RM122`, and 40 more are proposed. An agent made the scheme, and the owner was never asked about it.

Research batch RB-0075 (evidence: [../research/0018-respell-research-method-ids.md](../research/0018-respell-research-method-ids.md)) found:

- The build scripts give a method its number from its place in the list, so rebuilding or re-sorting the list would renumber methods.
- The scripts read the catalogue from a copy on one machine, not from the Research repo.
- Every RM number checked means one method and nothing else, so the IDs can be renamed by script.
- `RM33` has a different shape from `D-0007`, `REQ-0022` and `RB-0075`.

On 2026-10-23 at 05:18 UTC the owner chose `RM-0001` style, renamed everywhere, on a decision card that offered keeping `RM01` with only the numbering fixed, or leaving it as it is. Earlier that day the owner said that the cost of keeping an agent-made scheme is not a reason to keep it in a greenfield system (D-0014).

## Decision Drivers

- **One shape for every cited ID:** `D-0007`, `REQ-0022`, `STD-0001`, `RB-0075`.
- **A number stays with its method:** the published catalogues read, such as MITRE ATT&CK, mark retired entries and point to their replacement instead of deleting them.
- **Greenfield:** the IDs have no users outside the project. central-hub cites none.
- **Replaceable** (REQ-0011).

## Considered Options

1. **`RM-NNNN`, stored numbers, renamed everywhere.**
2. **Keep `RMnn`, store the numbers and register it as it is.** It fixes the numbering for little cost, but keeps a different shape.
3. **Leave it as it is.** List-position numbering stays a risk.

## Decision Outcome

Chosen option: **1**, which the owner chose on 2026-10-23 at 05:18 UTC.

This adds the Research methods row to D-0003's registry, and D-0003 rule 6 says how a retired method is kept.

### The methods catalogue

- The catalogue stays one JSON file in the Research repo. Each method's `id` field is its number, and no script works it out from the list.
- A new method gets a number only after the owner says yes to adding it. RB-0055's 40 proposed methods have no number until then.
- The Research repo copy is the only source. Scripts that read another copy are changed to read this one.
- A check fails on a duplicate number, a number not in `RM-NNNN` form, or a cited ID with no catalogue row.

### The method rename

- `RM01` to `RM122` become `RM-0001` to `RM-0122`, keeping their numbers.
- The rename runs by script over the Research repo and the project files. It skips correction logs, whose "before" text must stay as it was, and the kept records under D-0003 rule 5.
- The research gate checks method IDs in every new SPEC. Its hook runs from the setup script, which the owner pastes by hand, so the new setup script goes to the owner in the same step as the rename. Until it is pasted, new SPECs would fail the gate.
- The full old-to-new list goes in a corrections log, not in this record.

### Order of work after acceptance

1. Research: store the numbers, fix the scripts and the checks, and prepare the rename.
2. The setup script with the updated gate: the agent drafts it, and the owner pastes it.
3. Research and project files: run the rename in the same step, and prove it with a search count of 0 old IDs outside the kept records.
4. Project instructions, if they cite a method ID: the agent drafts, the owner approves, and the coordinator saves.
5. central-hub: no live method IDs today, so no correction PR is expected.

### Consequences

- Good: every cited ID has one shape, and a method's number can no longer change by accident.
- Good: retired methods stay visible with a pointer to their replacement.
- Bad: about 10,700 renamed citations, and one setup-script change that the owner has to paste in step.
- Neutral: no method's name, content or sources change.

### Confirmation

- The catalogue check passes: no duplicate numbers and every ID in `RM-NNNN` form.
- After the rename, a search finds 0 `RMnn` IDs outside the kept records and correction logs, and the count goes in the corrections log.
- A new SPEC passes the research gate with `RM-NNNN` IDs.

## Pros and Cons of the Options

### 1. RM-NNNN, renamed everywhere
- Good: one shape for every ID, and numbers stored.
- Bad: the largest change, with a setup-script step.

### 2. Keep RMnn, store the numbers
- Good: fixes the numbering for little cost, and needs no hook change.
- Bad: keeps a shape different from every other registered family.

### 3. Leave it
- Good: no work.
- Bad: list-position numbering can renumber methods.

## More Information

- **Evidence:** [../research/0018-respell-research-method-ids.md](../research/0018-respell-research-method-ids.md)
- Earlier renames handled the same way: requirement IDs (D-0014) and research batch codes (D-0015).
- Related records: D-0001, D-0003, D-0006, D-0014, D-0015, D-0016.
