---
id: D-0014
title: Spell requirement IDs REQ-NNNN, and during Foundation rename agent-made labels everywhere with the owner's approval
status: accepted
date: 2026-10-23
decision-makers: [jon]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001, D-0004, D-0006, D-0009]
supersedes: [D-0009]
superseded-by:
accepted-evidence:
  quote: "accept PR jonhill90/central-hub#22 f62845a"
  message-id: cmsg_01X43rfNYp4H1dL1V2dkfkwN12EqNFjmi5fTVUJmrD9vhd
  timestamp: 2026-10-23T03:46:26Z
  approved-commit: f62845acd38deb7018acd8f96a2a484677976c8c
  merged: not yet; Jon merges PR #22, which carries this evidence commit on top of the approved commit
  quote-check: the drafting agent read the message in the "Requirements register and SR ids" thread at 2026-10-23T03:46Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
legacy-id: []
revisit-when: the Activation gate passes (rule 5 goes back to "never renamed"); a rename sweep leaves a reference that a search missed; or a requirements tool is adopted that brings its own ID scheme
---

# Spell requirement IDs REQ-NNNN, and during Foundation rename agent-made labels everywhere with the owner's approval

## Context and Problem Statement

On 2026-10-23 Jon said the requirement IDs (`SR01` to `SR25`) were made up by agents and never got the scrutiny other choices got. The check that followed (research batch RQ1, project files outside this repo at `research/requirement-ids/`) found:

- An agent coordinator wrote the `SR` format on 2026-10-06, before this project existed. Jon said yes to each requirement's wording, never to the format.
- The ID research behind D-0003 kept `SR` only because it did not clash, and froze its spelling ("Nothing is respelled"). D-0009 carried it over unchanged.
- `SR` does not match the house style the other families use (`D-0007`, `STD-0001`: a dash and four digits).
- Outside the project, NIST SP 800-53 already uses `SR` for its Supply Chain Risk Management controls (`SR-3`). Under D-0009 rule 2, `SR` also blocks any future prefix that starts with `SR`.

Jon chose `REQ-0000` style on 2026-10-23 at 03:38 UTC: "I like REQ-0000 more and because its already oneway in a pretty much greenfield system does not seem like a good reason. its just words. we should fix them if we can. same with the other IDs."

D-0009 rule 5 ("Old labels are never renamed") would keep `SR11` alive beside `REQ-0011` forever. Jon wants the fix applied everywhere, the way agent-made method IDs were fixed on 2026-10-18 ("like it never happened").

## Decision Drivers

- **Match what exists:** `D-0007` and `STD-0001` use a dash and four digits.
- **One name per thing:** two live names for one requirement is the confusion R3 measured (`P1` had 7 meanings).
- **Greenfield:** Foundation is the cheapest time to rename. The count of `SR` references grows every day (about 4,700 on 2026-10-23).
- **Records stay true:** chat archives and git history are records of what was said and must not change.
- **Replaceable** (requirement SR11, which this record renames `REQ-0011`).

## Considered Options

1. **`REQ-NNNN`, renamed everywhere during Foundation, with one corrections log.**
2. **`REQ-NNNN` for new citations only, with `SR..` kept as each row's old label** (D-0009 rule 5 as written).
3. **Keep `SRNN`** and only write the format down (the agent's first draft v0.1).

## Decision Outcome

Chosen option: **1**, which Jon chose on 2026-10-23 at 03:38 UTC.

D-0009's rules 1, 2, 3, 4, 6 and 7 carry over unchanged. Rule 1's registry row for requirements changes, and rule 5 gets a Foundation exception. All rules are restated here, so this record stands alone once it supersedes D-0009.

### The rules

1. **Global IDs are only for things cited across files, repos and chats.** These are the registered families:

   | Family | Pattern | Example | Home register | Who numbers it |
   |---|---|---|---|---|
   | Decisions | `D-NNNN` | `D-0007` | central-hub `docs/decisions/` | Set by D-0001: the number is assigned when the PR opens |
   | Requirements | `REQ-NNNN` | `REQ-0022` | Research `coordinator/system/REQUIREMENTS.md` | The requirements register owner: the next number is assigned only after Jon says yes to the wording |
   | Standards | `STD-NNNN` | `STD-0001` | central-hub `docs/standards/` | The standards register owner: the number is assigned when the standard's PR opens |

   The `SR` family is retired. A sources family is still left out.

2. **One family registry.** The table above is the family registry. A change to it is a new decision record that supersedes this one.
   - A new family is added only with Jon's approval.
   - A new prefix must have at least two characters and must not equal or start with an existing one, ignoring case. `REQ-` passes this check against `D-` and `STD-`.
3. **Number late, with one owner per family.** A draft has no number and is cited by its file path (`D-TBD`, `STD-TBD`, `REQ-TBD`). Check that the number is unique before merging. Outside rule 5's Foundation exception, a number never changes after it is assigned.
4. **Everything else is a local label.** Outside its own file, write it with the file name: `DECISION-MAP#P1`. A bare one-letter label outside its own file is a mistake that reviewers flag.
5. **Old labels are not renamed, except during Foundation.**
   - Until the Activation gate passes, Jon may approve renaming an agent-made ID or label. The rename is then applied to every live file in central-hub, the Research repo and the project files, so the files read as if the new name had always been used. No inline "was SR11" notes.
   - One corrections log per rename holds every old-to-new pair, the date and Jon's approval. Git history keeps the rest.
   - Records of what was said are never changed: the chat archive, captured transcripts and git history keep the old names.
   - Accepted decision records are corrected in place under D-0006, because a rename does not change any decision. Each correction PR lists every change, and Jon approves it by PR number and head SHA.
   - After the Activation gate passes, the old rule returns: when an item gets a new ID, its record lists the old one in `legacy-id`.
6. **Never reuse, never delete.** A superseded or withdrawn item keeps its ID, its status and a link to whatever replaced it. D-0004's Foundation exception for void IDs still applies.
7. **Keep meaning out of the number.** The prefix names the family and nothing else.

### The requirements rename

- `SR01` to `SR25` become `REQ-0001` to `REQ-0025`, keeping their numbers.
- `SR16a` stays `REQ-0016`. `SR16b` becomes `REQ-0026`, the next free number, so every ID has the same shape.
- The register's tombstone "Former SR21 (void)" becomes "Former REQ-0021 (void)".

### Order of work after acceptance

1. Research: the register, its Library copy, and the register check (`check_register.py` matches `SR\d\d[a-z]?` today), with its tests.
2. Project instructions: the agent drafts the new text, Jon approves it, and the coordinator saves it.
3. central-hub: one correction PR for every `SR` reference (63 on 2026-10-23), under rule 5 and D-0006.
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

### 3. Keep SRNN
- Good: no change at all.
- Bad: keeps an agent-made format Jon never chose, the NIST clash and the blocked prefixes.

## More Information

- Research (project files outside this repo): `research/requirement-ids/` (SYNTHESIS.md, LEDGER.md). Research repo copy: `areas/documentation/research/requirement-ids/`.
- Earlier rename handled the same way: research method IDs, 2026-10-18 (batch MF1, project files `research/method-id-fixes/CORRECTIONS.md`).
- Related records: D-0001, D-0003, D-0004, D-0006, D-0009.
- On acceptance, D-0009's lifecycle fields change to `status: superseded` and `superseded-by: D-0014`, under D-0001.

_Jon's quoted words are shown as he wrote them._
