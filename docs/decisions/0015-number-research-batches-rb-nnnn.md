---
id: D-0015
title: Number research batches RB-NNNN in one batch register, and rename the old batch codes everywhere
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
  check: the drafting agent read the message in the "Requirements register and SR ids" thread at 2026-10-23T04:21Z, and the recorded wording matched it exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: PR #24 merged at 2026-10-23T04:22Z as 7b7a6b6, with this evidence commit on top of the approved commit
legacy-id: []
revisit-when: the Activation gate passes; the Research repo is retired and research moves somewhere with its own numbering; or a batch register check finds a duplicate number
---

# Number research batches RB-NNNN in one batch register, and rename the old batch codes everywhere

## Context and Problem Statement

A research batch is one piece of research with its own folder and SPEC.md, kept outside this repo (the Research repo and the project files). Batches are cited from this repo, from chats and from each other by a short code such as `R3`, `RR1` or `CKA1`.

Agents made those codes up one at a time. Research batch RB-0074 ([evidence](../research/0015-number-research-batches-rb-nnnn.md)) measured them on 2026-10-23:

- 75 folders carry a code, written in 9 different shapes (`R3`, `RR1`, `R11b`, `ROUT-1`, `ADR-C1`, `cncf-catalogue`, and others). Nothing defines how a code is made.
- 3 codes name two different batches each: `RR1`, `AT1` and `VN1`.
- Some codes look like other labels: `SR1` looks like the old `SR` requirement IDs, and `K1` and `V1` already mean other things.

Under D-0003 rule 5, the owner may approve renaming an agent-made label during Foundation. On 2026-10-23 at 04:16 UTC the owner chose RB-0001 style, renamed everywhere, on a decision card (message cmsg_01X43rfNYp4H1dL1V2dkfkwNQcYS9um5zKTC7zv6b3o1qM).

## Decision Drivers

- **One name per thing:** a code that names two batches cannot be cited safely.
- **Match what exists:** `D-0007`, `REQ-0022` and `STD-0001` use a prefix, a dash and four digits.
- **How others do it:** Python PEPs, Kubernetes KEPs, IETF RFCs and ClinicalTrials.gov each hand out a plain number from one registry and keep the readable name beside it (RB-0074, evidence finding 4).
- **Greenfield:** renaming is cheapest now.
- **Replaceable** (REQ-0011).

## Considered Options

1. **`RB-NNNN` from one batch register, old codes renamed everywhere.**
2. **No codes: cite each batch by its folder path.** Nothing new to keep, but folder names already differ between the project files and the Research repo, and folders move.
3. **A different prefix.**

## Decision Outcome

Chosen option: **1**, which the owner chose on 2026-10-23 at 04:16 UTC.

This adds the Research batches row to D-0003's registry. `RB-` passes D-0003 rule 2's prefix check against `D-`, `REQ-` and `STD-`.

### The batch register

- One Markdown table, one row per batch: ID, folder, question, SPEC date, status. It lives in the Research repo beside the batch folders.
- A batch is numbered when its SPEC.md is written, because the SPEC is how a batch is registered. An idea with no SPEC has no number.
- The folder name stays the batch's readable name. Folders are not renamed by this record.
- A check fails when two rows share a number or a batch folder has no row.

### The batch rename

- The rename covers clear batch citations: an old code written as a batch citation. On 2026-10-23 at 04:34 UTC the owner chose this scope, on a decision card that measured about 23,000 matches of the old code shapes.
- The batches that exist on acceptance are numbered `RB-0001` onward in order of their SPEC date. Ties break by the first git commit of the SPEC.md. A SPEC with no date takes its first commit date.
- One batch copied under two folder names (`R1`, `DG1`) gets one number. Codes that are aliases or parts of another batch (`RM2`, `R2b`) map to that batch's number.
- Each of the three clashing codes (`RR1`, `AT1`, `VN1`) is renamed only after its citation is read in context to tell which batch it means. About 280 citations need that read. Every other code is renamed by script.
- The full old-to-new list goes in the corrections log, not in this record.

### Order of work after acceptance

1. Research: write the batch register and its check.
2. Research and project files: rename every explicit batch citation with an old code, read the clashing ones in context, and prove it with a search count of 0 explicit batch citations with an old code outside the kept records.
3. Project instructions: the agent drafts any changed text, the owner approves it, and the coordinator saves it.
4. central-hub: one correction PR for every old batch code in accepted records and the PRD, under D-0003 rule 5 and D-0006.

### Consequences

- Good: every batch has one name in one shape, and the three clashes end.
- Good: a register shows every batch, its question and its status in one place.
- Bad: a one-time sweep, with about 280 citations read by hand.
- Bad: old chats and git history keep the old codes, so a reader of old chats needs the corrections log.
- Neutral: no batch's content, folder or findings change.

### Confirmation

- The batch register check passes: no duplicate number, no batch folder without a row.
- After the sweep, a search of every live file finds 0 explicit batch citations with an old code outside the kept records, and the count is recorded in the corrections log.
- The D-0003 review checks still apply: bare one-letter labels, non-unique global IDs, and prefixes missing from the registry.

## Pros and Cons of the Options

### 1. RB-NNNN, renamed everywhere
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
- Earlier renames handled the same way: requirement IDs (D-0014, corrections log in project files `research/requirement-ids/CORRECTIONS.md`) and research method IDs (2026-10-18, project files `research/method-id-fixes/CORRECTIONS.md`).
- Related records: D-0001, D-0003, D-0004, D-0006, D-0009, D-0014.
