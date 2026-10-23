---
id: D-0018
title: Spell research method IDs RM-NNNN, store each method's number, and rename the old IDs everywhere
status: proposed
date: 2026-10-23
decision-makers: [jon]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001, D-0006, D-0015, D-0016]
supersedes: [D-0015]
superseded-by:
accepted-evidence:
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

Adding a family changes the family registry, so under D-0015 rule 2 it needs a record that supersedes D-0015.

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

D-0015's rules all carry over. Rule 1 gains one registry row, and rule 6 adds how a retired method is kept. They are restated here so this record stands alone once it supersedes D-0015.

### The rules

1. **Global IDs are only for things cited across files, repos and chats.** These are the registered families:

   | Family | Pattern | Example | Home register | Who numbers it |
   |---|---|---|---|---|
   | Decisions | `D-NNNN` | `D-0007` | central-hub `docs/decisions/` | Set by D-0001: the number is assigned when the PR opens |
   | Requirements | `REQ-NNNN` | `REQ-0022` | Research `coordinator/system/REQUIREMENTS.md` | The requirements register owner: the next number is assigned only after the owner says yes to the wording |
   | Standards | `STD-NNNN` | `STD-0001` | central-hub `docs/standards/` | The standards register owner: the number is assigned when the standard's PR opens |
   | Research batches | `RB-NNNN` | `RB-0074` | Research `areas/documentation/research/BATCHES.md` | The batch register owner: the number is assigned when the batch's SPEC.md is written |
   | Research methods | `RM-NNNN` | `RM-0033` | Research `areas/research-tooling/research/research-methods-crawl/methods/inventory.json` | The methods catalogue owner: the number is stored with the method and assigned only after the owner says yes to adding it, never from its place in the list |

   The `SR` family stays retired. A sources family is still left out.

2. **One family registry.** The table above is the family registry. A change to it is a new decision record that supersedes this one.
   - A new family is added only with the owner's approval.
   - A new prefix must have at least two characters and must not equal or start with an existing one, ignoring case. `RM-` passes this check against `D-`, `REQ-`, `STD-` and `RB-`.
3. **Number late, with one owner per family.** A draft has no number and is cited by its file path (`D-TBD`, `REQ-TBD`, `STD-TBD`, `RB-TBD`, `RM-TBD`). Check that the number is unique before merging. Outside rule 5's Foundation exception, a number never changes after it is assigned.
4. **Everything else is a local label.** Outside its own file, write it with the file name: `DECISION-MAP#P1`. A bare one-letter label outside its own file is a mistake that reviewers flag.
5. **Old labels are not renamed, except during Foundation.**
   - Until the Activation gate passes, the owner may approve renaming an agent-made ID or label. The rename is then applied to every live file in central-hub, the Research repo and the project files, so the files read as if the new name had always been used. No inline "was SR11" notes.
   - One corrections log per rename holds every old-to-new pair, the date and the owner's approval. Git history keeps the rest.
   - Records of what was said are never changed: the chat archive, captured transcripts and git history keep the old names.
   - Accepted decision records are corrected in place under D-0006, because a rename does not change any decision. Each correction PR lists every change, and the owner approves it by PR number and head SHA.
   - After the Activation gate passes, the old rule returns: when an item gets a new ID, its record lists the old one in `legacy-id`.
6. **Never reuse, never delete.** A superseded or withdrawn item keeps its ID, its status and a link to whatever replaced it. A retired method stays in the catalogue, marked `deprecated` or `replaced by RM-NNNN`. D-0004's Foundation exception for void IDs still applies.
7. **Keep meaning out of the number.** The prefix names the family and nothing else. A batch that continues another says so in its SPEC.md ("follows RB-0006"), not in its number.

### The methods catalogue

- The catalogue stays one JSON file in the Research repo. Each method's `id` field is its number, and no script works it out from the list.
- A new method gets a number only after the owner says yes to adding it. RB-0055's 40 proposed methods have no number until then.
- The Research repo copy is the only source. Scripts that read another copy are changed to read this one.
- A check fails on a duplicate number, a number not in `RM-NNNN` form, or a cited ID with no catalogue row.

### The method rename

- `RM01` to `RM122` become `RM-0001` to `RM-0122`, keeping their numbers.
- The rename runs by script over the Research repo and the project files. It skips correction logs, whose "before" text must stay as it was, and the kept records under rule 5.
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
- Related records: D-0001, D-0006, D-0014, D-0015, D-0016, D-0017.
- On acceptance, D-0015's lifecycle fields change to `status: superseded` and `superseded-by: D-0018`, under D-0001.
