---
id: D-0009
title: Add a STD- family for standards to the ID family registry
status: superseded
date: 2026-10-22
decision-makers: [jon]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0003]
supersedes: [D-0003]
superseded-by: D-0014
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-22T02:52:24Z
  approved-commit: a4f05820ec546535d980c8f660cb693c70ca64cf
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNU91iAKVLo8uUHycWbJs6MY
  approval-names: "PR #14 and head a4f0582, in the message itself"
  check: the drafting agent read the message in the Standards system thread at 2026-10-22T02:52Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; Jon merges PR #14, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: the same as D-0003, plus: the standards register moves out of this repo; or a second kind of standard needs its own family
---

# Add a STD- family for standards to the ID family registry

## Context and Problem Statement

On 2026-10-21 Jon asked whether the project needs a system for its standards. The rules he has said yes to are spread across many files, for example VM hostnames (option E), the repo layout rules and the backlog status words. On 2026-10-21 at 02:00 UTC he said yes to the proposed answer: one standards register, a subsystem of system 2 Organization.

Standards will be cited across files, repos and chats, for example by AGENTS.md, by check scripts and by decision records. D-0003 rule 1 says such items get a global ID. D-0003 rule 2 says a new family is added only with Jon's approval, by a new record that supersedes D-0003.

On 2026-10-22 at 02:48 UTC Jon chose option A, `STD-NNNN`, from four ID options:

- A. `STD-0001`, a number only.
- B. `STD-NAME-01`, with the topic inside the ID.
- C. No global family, only a file label such as `STANDARDS#vm-hostname`.
- D. Reuse the decision ID `D-NNNN`.

## Decision Drivers

- **Fit D-0003.** The new prefix must have at least two characters and must not equal or start with an existing prefix, ignoring case. Meaning stays out of the number.
- **Match what exists.** Decisions are written `D-0007`, with a dash and four digits.
- **One standard, one ID**, separate from the decision that set it. One decision can set several standards, and a standard can change while its decision stays as history.
- **Replaceable** (REQ-0011).

## Considered Options

1. **A. `STD-NNNN`**, numbered by one owner.
2. **B. `STD-<TOPIC>-NN`.** This breaks D-0003 rule 7, and moving a standard to another topic would change its ID.
3. **C. File labels only.** This breaks D-0003 rule 1 once standards are cited across repos.
4. **D. Reuse `D-NNNN`.** This mixes standards with decisions.

## Decision Outcome

Chosen option: **1, `STD-NNNN`**, which Jon chose on 2026-10-22 at 02:48 UTC.

D-0003's rules 1 and 3 to 7 carry over unchanged. Rule 2 gets one more row in the registry. They are restated here, so this record stands alone once it supersedes D-0003.

### The rules

1. **Global IDs are only for things cited across files, repos and chats.** These are the registered families:

   | Family | Pattern | Example | Home register | Who numbers it |
   |---|---|---|---|---|
   | Decisions | `D-NNNN` | `D-0007` | central-hub `docs/decisions/` | Set by D-0001: the number is assigned when the PR opens |
   | Requirements | `SRNN` | `SR22` | Research `coordinator/system/REQUIREMENTS.md` | The Research requirements owner |
   | Standards | `STD-NNNN` | `STD-0001` | central-hub `docs/standards/` | The standards register owner: the number is assigned when the standard's PR opens |

   A sources family is still left out, as in D-0003.

2. **One family registry.** The table above is the family registry. It lives in this record until it needs its own file. A change to it is a new decision record that supersedes this one.
   - A new family is added only with Jon's approval.
   - A new prefix must have at least two characters and must not equal or start with an existing one, ignoring case. `STD-` passes this check against `D-` and `SR`.
   - A future sources family must not use `SRC-` without checking it against `SR` under this rule.
3. **Number late, with one owner per family.** A draft has no number and is cited by its file path (`D-TBD`, `STD-TBD`). Check that the number is unique before merging. A number never changes after it is assigned.
4. **Everything else is a local label.** Outside its own file, write it with the file name: `DECISION-MAP#P1`, `LIVE-PARAMETERS#S1`. A bare one-letter label outside its own file is a mistake that reviewers flag.
5. **Old labels are never renamed.** When an item gets a global ID, its record lists the old label, written with its file name, in `legacy-id`.
6. **Never reuse, never delete.** A superseded or withdrawn item keeps its ID, its status and a link to whatever replaced it.
7. **Keep meaning out of the number.** The prefix names the family and nothing else. Topic, status and owner go in front matter or in the register's columns, never in the ID.

### Not decided here

- the columns, status words and file format of the standards register;
- which standards it holds first;
- whether system 2 Organization's other records live in `docs/standards/` too.

### Consequences

- Good: a standard can be cited anywhere as `STD-0001`, the same way decisions are.
- Good: a standard keeps its ID when its topic, owner or wording changes.
- Bad: one more family, so the registry is one row longer.
- Bad: `STD-0001` does not say what the standard is about without a lookup. This is the same trade D-0003 made for `D-NNNN`.
- Neutral: no standard is numbered by this record. The `docs/standards/` folder appears with its first real file (D-0008 rule 5).

### Confirmation

- A reviewing agent checks each new standard for a unique `STD-` number, and checks that no ID carries a topic.
- The D-0003 review checks still apply: bare one-letter labels, non-unique global IDs, and prefixes missing from the registry.

## Pros and Cons of the Options

### B. Topic in the ID
- Good: readable without a lookup.
- Bad: breaks rule 7. Moving a standard to another topic changes its ID, and the repos checked for D-0003 that keep identity apart from meaning held up best.

### C. File labels only
- Good: nothing new to register.
- Bad: breaks rule 1 once AGENTS.md or another repo cites a standard. Moving the file changes every label.

### D. Reuse `D-NNNN`
- Good: no new family.
- Bad: one decision can set several standards, and a standard changes while its decision stays as history.

## More Information

- Proposal and ID options (project files outside this repo): `plans/standards-system/PROPOSAL-v0.1.md`, §6.
- **Evidence:** no research batch of its own. Its ID rules rest on D-0003's research: [../research/0003-use-registered-id-families-and-file-qualified-labels.md](../research/0003-use-registered-id-families-and-file-qualified-labels.md).
- Related records: D-0001, D-0003, D-0004, D-0008.
- On acceptance, D-0003's lifecycle fields change to `status: superseded` and `superseded-by: D-0009`, under D-0001.

## Corrections

- **2026-10-23** (requirement IDs respelled under D-0014): 1 requirement ID renamed, `SR11` to `REQ-0011`. Before: `SR11`; after: `REQ-0011`, and the same for each pair listed. Reason: D-0014 retires the `SR` spelling and its rule 5 renames live references in place; no decision changes. Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23).
- **2026-10-23** (research batch IDs under D-0015): 1 research batch citation renamed: `R3` to `RB-0003`. Reason: D-0015 numbers research batches `RB-NNNN`, and its rule 5 renames live references in place; no decision changes. Approval: the owner, 2026-10-23T04:59:42Z (approval-ref cmsg_01X43rfNYp4H1dL1V2dkfkwN7qM5qKKp8HDEfuF6EYoQkC), naming PR #27 and head 8d63c29; approved commit 8d63c29543a8adccdebb9704146d067b238e1c54. Check: the drafting agent read the message at 2026-10-23T04:59Z and confirmed it names that PR and head.
- **2026-10-23** (owner's words and approvals recorded in neutral form under D-0016). Reason: D-0016 rules 5 to 7 and its "What happens to the existing records"; no decision changes. Where the text removed is the owner's words, this entry names where it was and a commit that holds it (ba5bb20) instead of copying it (D-0016 rule 7).
  1. `accepted-evidence` rewritten once into D-0016 rule 6 fields with D-0006 step 7's fixed mapping, as amended by D-0016: `timestamp` to `approved-at`, `message-id` to `approval-ref`, `quote-check` to `check`; `approved-by: owner` and `approval-names` added; `quote` removed (its text is in `accepted-evidence.quote` at commit ba5bb20). No value changes.
  2. Context and Problem Statement, first paragraph: the quote of Jon's 2026-10-21 question (at commit ba5bb20) replaced by a neutral summary. After: "On 2026-10-21 Jon asked whether the project needs a system for its standards."
  3. More Information, second bullet. Before: "Research behind the ID rules: batch RB-0003, `central-hub/research/identifiers/` in the project files, as cited by D-0003." After: "**Evidence:** no research batch of its own. Its ID rules rest on D-0003's research: [../research/0003-use-registered-id-families-and-file-qualified-labels.md](../research/0003-use-registered-id-families-and-file-qualified-labels.md)." Reason: the old pointer is private; D-0016 rule 2.
  4. The 2026-10-23 requirement-ID entry above: its approval, which quoted the approval message (at commit ba5bb20), rewritten as D-0016 rule 6 facts. After: "Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23)." No value changes.

  Approval: to be added after approval (D-0006 step 6).
