---
id: D-0010
title: Give specs five status words
status: accepted
date: 2026-10-22
decision-makers: [owner]
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
  check: the drafting agent read the message in the PRD and spec research thread at 2026-10-22T07:03Z, and the recorded wording matched it exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: PR #15 merged at 2026-10-22T07:03Z as 06ac6b9, with this evidence commit on top of the approved commit
revisit-when: specs pile up in accepted with no one finishing them; a check script starts reading the status field; or a second repo adopts specs
---

# Give specs five status words

## Context and Problem Statement

D-0007 and D-0008 set the rules and names for the PRD and specs. Two points stopped a first spec from being written: the status words for specs, and what happens to the earlier documentation-contract and first-slice drafts.

On 2026-10-22 at 06:57 UTC the owner asked for help getting this process ready, so that it could start being used.

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

Chosen option: **1**. The owner said yes to the proposed option on 2026-10-22 at 07:02 UTC, on a decision card that asked: "Make the PRD and spec process ready with these four pieces in one PR?" That answer chose the option. The owner accepted this record under D-0001 on 2026-10-22 at 07:03 UTC.

### Rules

1. **Status words.** A spec's `status` is one of:
   - `proposed`: written on the change's branch, PR open;
   - `accepted`: the owner accepted it with a message naming the PR number and head SHA; work may start;
   - `done`: the change is finished and its acceptance criteria pass;
   - `dropped`: stopped before it was done, with the reason in the spec's decision log;
   - `superseded`: a newer spec replaces it, named in `superseded-by`.
2. **Who moves a spec.** Agents write only `proposed`. Every later status change rides on a PR that the owner accepts the same way, with a message naming the PR number and head SHA.
3. **Evidence fields.** A spec's front matter has `accepted-evidence` and `done-evidence`, in the same shape as a decision record's `accepted-evidence`.
4. **Replaced drafts.** The three earlier Research drafts (platform PRD, documentation contract, first-slice spec) are replaced by `docs/PRD.md`, by D-0007, D-0008 and this record, and by the first spec in `docs/specs/`.
5. **Where it is written down.** `docs/specs/README.md` holds the steps, a template and the index. This record is the source if the two differ.

### Not decided here

- which store holds one system's PRD and specs about another system;
- whether a decision record may be edited before it is implemented.

### Consequences

- Good: a spec can be written today. The first one is expected to be the first build.
- Good: anyone who knows the decision record words can read a spec's status.
- Bad: two more status words than the minimum; `dropped` and `superseded` may sit unused for a while.
- Neutral: `done` needs one more PR at the end of the work. That PR is where the acceptance criteria are shown passing.

### Confirmation

- Every spec in `docs/specs/` has one of the five words in `status`.
- Each status after `proposed` has evidence naming the owner's message.

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
