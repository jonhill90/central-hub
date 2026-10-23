---
id: D-0010
title: Give specs five status words and retire the three October 2026 drafts
status: accepted
date: 2026-10-22
decision-makers: [jon]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0007, D-0008]
supersedes: []
superseded-by:
accepted-evidence:
  quote: "accept PR jonhill90/central-hub#15 b32bd59"
  message-id: cmsg_01X43rfNYp4H1dL1V2dkfkwNG5mGAoayYeUHQvQF3FC42W
  timestamp: 2026-10-22T07:03:02Z
  approved-commit: b32bd599bdac76aa63f5fdf4c227688e13894513
  merged: not yet; Jon merges PR #15, which carries this evidence commit on top of the approved commit
  quote-check: the drafting agent read the message in the PRD and spec research thread at 2026-10-22T07:03Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
legacy-id: []
revisit-when: specs pile up in accepted with no one finishing them; a check script starts reading the status field; or a second repo adopts specs
---

# Give specs five status words and retire the three October 2026 drafts

## Context and Problem Statement

D-0007 and D-0008 set the rules and names for the PRD and specs. Two of the points they left open stop a first spec from being written: "the status words for specs" and "what happens to the documentation-contract and first-slice drafts" (D-0007, "Not decided here").

On 2026-10-22 at 06:57 UTC Jon asked: "I need some help here. i think we need this process ready so we can start using it."

## Decision Drivers

- **One vocabulary.** Decision records already use `proposed`, `accepted` and `superseded` (D-0001). Specs should reuse those words, not add near-synonyms.
- **D-0007 rule 5.** A spec carries a status field, and its body is frozen once it is accepted.
- **One PRD** (D-0007 rule 1). The October 2026 drafts describe a knowledge-API first slice that the current platform plan has replaced.
- **Replaceable** (REQ-0011).

## Considered Options

1. **Five words:** `proposed`, `accepted`, `done`, `dropped`, `superseded`.
2. **Three words:** `proposed`, `accepted`, `done`.
3. **Kubernetes KEP words:** `provisional`, `implementable`, `implemented`, `deferred`, `rejected`, `withdrawn`, `replaced`.

## Decision Outcome

Chosen option: **1**. Jon said yes to the proposed option on 2026-10-22 at 07:02 UTC, on a decision card that asked: "Make the PRD and spec process ready with these four pieces in one PR?" That answer chose the option. Jon accepted this record under D-0001 on 2026-10-22 at 07:03 UTC.

### Rules

1. **Status words.** A spec's `status` is one of:
   - `proposed`: written on the change's branch, PR open;
   - `accepted`: Jon accepted it with a message naming the PR number and head SHA; work may start;
   - `done`: the change is finished and its acceptance criteria pass;
   - `dropped`: stopped before it was done, with the reason in the spec's decision log;
   - `superseded`: a newer spec replaces it, named in `superseded-by`.
2. **Who moves a spec.** Agents write only `proposed`. Every later status change rides on a PR that Jon accepts the same way, with a message naming the PR number and head SHA.
3. **Evidence fields.** A spec's front matter has `accepted-evidence` and `done-evidence`, in the same shape as a decision record's `accepted-evidence`.
4. **Retired drafts.** Three drafts in the Research repo are replaced and stop being worked on. Each gets a header line naming what replaced it. Their bodies stay as they are, as history.
   - `areas/knowledge-architecture/platform-foundation/PLATFORM-PRD-DRAFT.md` is replaced by `docs/PRD.md`.
   - `areas/organization/platform-foundation/DOCUMENTATION-CONTRACT-DRAFT.md` is replaced by D-0007, D-0008 and this record.
   - `coordinator/platform-startup/FIRST-SLICE-SPEC-DRAFT.md` is replaced by the first spec in `docs/specs/`.
5. **Where it is written down.** `docs/specs/README.md` holds the steps, a template and the index. This record is the source if the two differ.

### Not decided here

- which store holds one system's PRD and specs about another system;
- whether a decision record may be edited before it is implemented;
- a check that fails on a dead link to code;
- the runbook format.

### Consequences

- Good: a spec can be written today. The first one is expected to be the first build.
- Good: anyone who knows the decision record words can read a spec's status.
- Bad: two more status words than the minimum; `dropped` and `superseded` may sit unused for a while.
- Neutral: `done` needs one more PR at the end of the work. That PR is where the acceptance criteria are shown passing.

### Confirmation

- Every spec in `docs/specs/` has one of the five words in `status`.
- Each status after `proposed` has evidence naming Jon's message.
- The three Research drafts each carry their "replaced by" line.

## Pros and Cons of the Options

### 2. Three words
- Good: smallest.
- Bad: a stopped or replaced spec would have to stay `accepted`, which reads as live work.

### 3. KEP words
- Good: proven on a large project.
- Bad: seven new words that differ from the decision record words.

## More Information

- Research behind it: Research repo, `areas/documentation/research/prd-spec-ps3/` (SYNTHESIS §1 shape B; ORG-CHECK, "What changes", item 4).
- Related records: D-0001, D-0007, D-0008.

## Corrections

- **2026-10-23** (requirement IDs respelled under D-0014): 1 requirement ID renamed, `SR11` to `REQ-0011`. Before: `SR11`; after: `REQ-0011`, and the same for each pair listed. Reason: D-0014 retires the `SR` spelling and its rule 5 renames live references in place; no decision changes. Approval: Jon, "approve PR jonhill90/central-hub#23 cabb14e" (message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, 2026-10-23T04:04:08Z); approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23).
