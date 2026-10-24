---
id: D-0014
title: Spell requirement IDs REQ-NNNN, and during Foundation rename agent-made labels everywhere with the owner's approval
status: accepted
date: 2026-10-23
decision-makers: [jon]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001, D-0003, D-0004, D-0006]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-23T03:46:26Z
  approved-commit: f62845acd38deb7018acd8f96a2a484677976c8c
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwN12EqNFjmi5fTVUJmrD9vhd
  approval-names: "PR #22 and head f62845a, in the message itself"
  check: the drafting agent read the message in the "Requirements register and SR ids" thread at 2026-10-23T03:46Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; Jon merges PR #22, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: the Activation gate passes (D-0003 rule 5 goes back to "never renamed"); a rename sweep leaves a reference that a search missed; or a requirements tool is adopted that brings its own ID scheme
---

# Spell requirement IDs REQ-NNNN, and during Foundation rename agent-made labels everywhere with the owner's approval

## Context and Problem Statement

On 2026-10-23 Jon said the requirement IDs (`SR01` to `SR25`) were made up by agents and never got the scrutiny other choices got. The check that followed (research batch RB-0072, [evidence](../research/0014-use-req-ids-for-requirements.md)) found:

- An agent coordinator wrote the `SR` format on 2026-10-06, before this project existed. Jon said yes to each requirement's wording, never to the format.
- The ID research behind D-0003 kept `SR` only because it did not clash, and froze its spelling ("Nothing is respelled"). The registry kept it when D-0009 added standards.
- `SR` does not match the house style the other families use (`D-0007`, `STD-0001`: a dash and four digits).
- Outside the project, NIST SP 800-53 already uses `SR` for its Supply Chain Risk Management controls (`SR-3`). Under D-0003 rule 2, `SR` also blocks any future prefix that starts with `SR`.

Jon chose `REQ-0000` style on 2026-10-23 at 03:38 UTC. Jon preferred it, and said that a format already in use is not a good reason to keep it in a system that is still almost greenfield: IDs are only words, they should be fixed where possible, and the same goes for the other IDs.

D-0003 rule 5, which then said old labels are never renamed, would keep `SR11` alive beside `REQ-0011` forever. Jon wants the fix applied everywhere, the way agent-made method IDs were fixed on 2026-10-18, so the files read as if the new name had always been used.

## Decision Drivers

- **Match what exists:** `D-0007` and `STD-0001` use a dash and four digits.
- **One name per thing:** two live names for one requirement is the confusion RB-0003 measured (`P1` had 7 meanings).
- **Greenfield:** Foundation is the cheapest time to rename. The count of `SR` references grows every day (about 4,700 on 2026-10-23).
- **Records stay true:** chat archives and git history are records of what was said and must not change.
- **Replaceable** (REQ-0011).

## Considered Options

1. **`REQ-NNNN`, renamed everywhere during Foundation, with one corrections log.**
2. **`REQ-NNNN` for new citations only, with `SR..` kept as each row's old label** (D-0003 rule 5 with no exception).
3. **Keep the `SR` IDs** and only write the format down (the agent's first draft v0.1).

## Decision Outcome

Chosen option: **1**, which Jon chose on 2026-10-23 at 03:38 UTC.

This changes the Requirements row of D-0003's registry to `REQ-NNNN`, and gives D-0003 rule 5 its Foundation exception: until the Activation gate passes, the owner may approve renaming an agent-made ID or label in every live file, with one corrections log per rename.

### The requirements rename

- `SR01` to `SR25` become `REQ-0001` to `REQ-0025`, keeping their numbers.
- `SR16a` stays `REQ-0016`. `SR16b` becomes `REQ-0026`, the next free number, so every ID has the same shape.
- The register's tombstone "Former SR21 (void)" becomes "Former REQ-0021 (void)".

### Order of work after acceptance

1. Research: the register, its Library copy, and the register check (`check_register.py` matches `SR\d\d[a-z]?` today), with its tests.
2. Project instructions: the agent drafts the new text, Jon approves it, and the coordinator saves it.
3. central-hub: one correction PR for every `SR` reference (63 on 2026-10-23), under D-0003 rule 5 and D-0006.
4. Research and project files: the rest of the sweep, proved by a search count of 0 live `SR` IDs.
5. Other agent-made ID schemes, one at a time in Jon's order, each with its own question.

### Consequences

- Good: requirements look like the other families, and `SR` no longer collides with NIST's family or blocks future prefixes.
- Good: each requirement has one name.
- Bad: a large one-time sweep (about 4,700 references) and one more correction PR on accepted records.
- Bad: the chat archive and git history keep the old names, so a reader of old chats needs the corrections log.
- Neutral: a requirement's wording and meaning do not change.

### Confirmation

- After the sweep, a search of every live file finds 0 `SR` requirement IDs, and the count is recorded in the corrections log.
- The register check fails on any `SR` ID in the register or in the project instructions.
- The D-0003 review checks still apply: bare one-letter labels, non-unique global IDs, and prefixes missing from the registry.

## Pros and Cons of the Options

### 1. REQ-NNNN, renamed everywhere
- Good: one name per requirement, and house style.
- Bad: the largest one-time effort.

### 2. REQ-NNNN for new citations only
- Good: no old file changes.
- Bad: two live names per requirement for as long as the old text is read.

### 3. Keep the SR IDs
- Good: no change at all.
- Bad: keeps an agent-made format Jon never chose, the NIST clash and the blocked prefixes.

## More Information

- **Evidence:** [../research/0014-use-req-ids-for-requirements.md](../research/0014-use-req-ids-for-requirements.md): batch RB-0072.
- Earlier rename handled the same way: research method IDs, 2026-10-18 (batch RB-0055, project files `research/method-id-fixes/CORRECTIONS.md`).
- Related records: D-0001, D-0003, D-0004, D-0006, D-0009.
