---
id: D-0015
title: Number research batches RB-NNNN
status: accepted
date: 2026-10-23
decision-makers: [owner]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001, D-0003, D-0006]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-23T04:21:52Z
  approved-commit: 1cce2f860ae2552047d2ba2b0bc960b45792bfda
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNNC2krzzxxNCskiWfAqbKzw
  approval-names: "PR #24 and head 1cce2f8, in the message itself"
  check: the drafting agent read the message in the requirements register thread at 2026-10-23T04:21Z, and the recorded wording matched it exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: PR #24 merged at 2026-10-23T04:22Z as 7b7a6b6, with this evidence commit on top of the approved commit
revisit-when: the Activation gate passes; the Research repo is retired and research moves somewhere with its own numbering; or a batch register check finds a duplicate number
---

# Number research batches RB-NNNN

## Context and Problem Statement

A research batch is one piece of research with its own folder and SPEC.md, kept outside this repo (the Research repo and the project files). Batches are cited from this repo, from chats and from each other.

Agents made up the batch codes one at a time. Research batch RB-0074 ([evidence](../research/0015-number-research-batches-rb-nnnn.md)) measured them on 2026-10-23:

- 75 folders carried a code, written in 9 different shapes. Nothing defined how a code is made.
- 3 codes each named two different batches.
- Some codes looked like other labels: IDs of another registered family, or labels that already meant other things.

On 2026-10-23 at 04:16 UTC the owner chose RB-0001 style, written the same way in every live file, on a decision card (message cmsg_01X43rfNYp4H1dL1V2dkfkwNQcYS9um5zKTC7zv6b3o1qM).

## Decision Drivers

- **One name per thing:** a code that names two batches cannot be cited safely.
- **Match what exists:** `D-0007`, `REQ-0022` and `STD-0001` use a prefix, a dash and four digits.
- **How others do it:** Python PEPs, Kubernetes KEPs, IETF RFCs and ClinicalTrials.gov each hand out a plain number from one registry and keep the readable name beside it (RB-0074, evidence finding 4).
- **Greenfield:** an ID is cheapest to fix during Foundation (D-0003 rule 5).
- **Replaceable** (REQ-0011).

## Considered Options

1. **`RB-NNNN` from one batch register, written the same way in every live file.**
2. **No codes: cite each batch by its folder path.** Nothing new to keep, but folder names already differ between the project files and the Research repo, and folders move.
3. **A different prefix.**

## Decision Outcome

Chosen option: **1**, which the owner chose on 2026-10-23 at 04:16 UTC.

This adds the Research batches row to D-0003's registry. `RB-` passes D-0003 rule 2's prefix check against `D-`, `REQ-` and `STD-`.

### The batch register

- One Markdown table, one row per batch: ID, folder, question, SPEC date, status. It lives in the Research repo beside the batch folders.
- A batch is numbered when its SPEC.md is written, because the SPEC is how a batch is registered. An idea with no SPEC has no number.
- The folder name stays the batch's readable name.
- A batch is cited by its `RB-NNNN` number.
- A check fails when two rows share a number or a batch folder has no row.

### Consequences

- Good: every batch has one name in one shape, and no number names two batches.
- Good: a register shows every batch, its question and its status in one place.
- Bad: one more register to keep current.
- Neutral: no batch's content, folder or findings depend on its number.

### Confirmation

- The batch register check passes: no duplicate number, no batch folder without a row.
- The D-0003 review checks still apply: bare one-letter labels, non-unique global IDs, and prefixes missing from the registry.

## Pros and Cons of the Options

### 1. RB-NNNN from one register

- Good: one name per batch, in house style, with one register.
- Bad: the largest one-time effort.

### 2. No codes, cite folder paths

- Good: nothing new to keep.
- Bad: folder names already differ between the project files and the Research repo, and a moved folder breaks every citation.

### 3. A different prefix

- Good: a prefix could say more than `RB`.
- Bad: nothing found that a longer prefix would fix, and longer IDs are cited thousands of times.

## More Information

- **Evidence:** [../research/0015-number-research-batches-rb-nnnn.md](../research/0015-number-research-batches-rb-nnnn.md): batch RB-0074.
- Related records: D-0001, D-0003, D-0004, D-0006, D-0009, D-0014.
