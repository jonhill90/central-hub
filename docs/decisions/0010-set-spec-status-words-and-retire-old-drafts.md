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
  approved-by: owner
  approved-at: 2026-10-22T07:03:02Z
  approved-commit: b32bd599bdac76aa63f5fdf4c227688e13894513
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNG5mGAoayYeUHQvQF3FC42W
  approval-names: "PR #15 and head b32bd59, in the message itself"
  check: the drafting agent read the message in the PRD and spec research thread at 2026-10-22T07:03Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; Jon merges PR #15, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: specs pile up in accepted with no one finishing them; a check script starts reading the status field; or a second repo adopts specs
---

# Give specs five status words and retire the three October 2026 drafts

## Context and Problem Statement

D-0007 and D-0008 set the rules and names for the PRD and specs. Two of the points they left open stop a first spec from being written: "the status words for specs" and "what happens to the documentation-contract and first-slice drafts" (D-0007, "Not decided here").

On 2026-10-22 at 06:57 UTC Jon asked for help getting this process ready, so that it could start being used.

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

- **Evidence:** no research batch of its own. It rests on D-0007's research: [../research/0007-use-a-one-page-prd-and-frozen-per-change-specs.md](../research/0007-use-a-one-page-prd-and-frozen-per-change-specs.md), findings 7 and 9.
- Related records: D-0001, D-0007, D-0008.

## Corrections

- **2026-10-23** (requirement IDs respelled under D-0014): 1 requirement ID renamed, `SR11` to `REQ-0011`. Before: `SR11`; after: `REQ-0011`, and the same for each pair listed. Reason: D-0014 retires the `SR` spelling and its rule 5 renames live references in place; no decision changes. Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23).
- **2026-10-23** (owner's words and approvals recorded in neutral form under D-0016). Reason: D-0016 rules 5 to 7 and its "What happens to the existing records"; no decision changes. Where the text removed is the owner's words, this entry names where it was and a commit that holds it (ba5bb20) instead of copying it (D-0016 rule 7).
  1. `accepted-evidence` rewritten once into D-0016 rule 6 fields with D-0006 step 7's fixed mapping, as amended by D-0016: `timestamp` to `approved-at`, `message-id` to `approval-ref`, `quote-check` to `check`; `approved-by: owner` and `approval-names` added; `quote` removed (its text is in `accepted-evidence.quote` at commit ba5bb20). No value changes.
  2. Context and Problem Statement, second paragraph: the quote of Jon's 06:57 UTC message (at commit ba5bb20) replaced by a neutral summary. After: "On 2026-10-22 at 06:57 UTC Jon asked for help getting this process ready, so that it could start being used."
  3. More Information, first bullet. Before: "Research behind it: Research repo, `areas/documentation/research/prd-spec-ps3/` (SYNTHESIS §1 shape B; ORG-CHECK, "What changes", item 4)." After: "**Evidence:** no research batch of its own. It rests on D-0007's research: [../research/0007-use-a-one-page-prd-and-frozen-per-change-specs.md](../research/0007-use-a-one-page-prd-and-frozen-per-change-specs.md), findings 7 and 9." Reason: the old pointers are private; D-0016 rule 2.
  4. The 2026-10-23 requirement-ID entry above: its approval, which quoted the approval message (at commit ba5bb20), rewritten as D-0016 rule 6 facts. After: "Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23)." No value changes.

  Approval: the owner, 2026-10-23T05:50:25Z (approval-ref cmsg_01X43rfNYp4H1dL1V2dkfkwNDAeh1xBwykD4qgSUzJ1UcQ), naming PR #31 and head eca96c0; approved commit eca96c04520789ec785fc4fd584c8f37a3b429f9. Check: the drafting agent read the message at 2026-10-23T05:50Z and confirmed it names that PR and head.
