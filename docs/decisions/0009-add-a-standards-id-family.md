---
id: D-0009
title: Add a STD- family for standards to the ID family registry
status: accepted
date: 2026-10-22
decision-makers: [jon]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0003]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-22T02:52:24Z
  approved-commit: a4f05820ec546535d980c8f660cb693c70ca64cf
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNU91iAKVLo8uUHycWbJs6MY
  approval-names: "PR #14 and head a4f0582, in the message itself"
  check: the drafting agent read the message in the Standards system thread at 2026-10-22T02:52Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; the owner merges PR #14, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: "the same as D-0003, plus: the standards register moves out of this repo; or a second kind of standard needs its own family"
---

# Add a STD- family for standards to the ID family registry

## Context and Problem Statement

On 2026-10-21 the owner asked whether the project needs a system for its standards. The rules he has said yes to are spread across many files, for example VM hostnames (option E), the repo layout rules and the backlog status words. On 2026-10-21 at 02:00 UTC he said yes to the proposed answer: one standards register, a subsystem of system 2 Organization.

Standards will be cited across files, repos and chats, for example by AGENTS.md, by check scripts and by decision records. D-0003 rule 1 says such items get a global ID. D-0003 rule 2 says a new family is added only with the owner's approval, by its own decision record.

On 2026-10-22 at 02:48 UTC the owner chose option A, `STD-NNNN`, from four ID options:

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

Chosen option: **1, `STD-NNNN`**, which the owner chose on 2026-10-22 at 02:48 UTC.

This adds the Standards row to the family registry in D-0003.

### Not decided here

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
- Bad: breaks D-0003 rule 7. Moving a standard to another topic changes its ID, and the repos checked for D-0003 that keep identity apart from meaning held up best.

### C. File labels only
- Good: nothing new to register.
- Bad: breaks D-0003 rule 1 once AGENTS.md or another repo cites a standard. Moving the file changes every label.

### D. Reuse `D-NNNN`
- Good: no new family.
- Bad: one decision can set several standards, and a standard changes while its decision stays as history.

## More Information

- Proposal and ID options (project files outside this repo): `plans/standards-system/PROPOSAL-v0.1.md`, §6.
- **Evidence:** no research batch of its own. Its ID rules rest on D-0003's research: [../research/0003-use-registered-id-families-and-file-qualified-labels.md](../research/0003-use-registered-id-families-and-file-qualified-labels.md).
- Related records: D-0001, D-0003, D-0004, D-0008.
