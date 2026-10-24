---
id: D-0006
title: Correct an accepted record in place when the decision does not change
status: accepted
date: 2026-10-16
decision-makers: [jon]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-16T08:28:58Z
  approved-commit: 0ae0493b4f6eef50aae6caa8a18c97d4515eab91
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNTJTUNZbcPsUxG7TCKiX23s
  approval-names: "PR #10 and head 0ae0493"
  check: the drafting agent read the message in the ADR corrections thread at 2026-10-16T08:29Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; the owner merges PR #10, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: agents get their own GitHub identities (Activation gate item 1); a correction is later found to have changed a decision; or corrections to one record pile up
---

# Correct an accepted record in place when the decision does not change

## Context and Problem Statement

As first written, D-0001 kept an accepted record's body unchanged and made every change a new record that superseded the old one. It had no separate path for an error that leaves the decision the same.

D-0005 was accepted on 2026-10-16 with two internal inconsistencies and a wording slip. The decision is unchanged, but D-0001 left only one route: a full restatement of D-0005 with three small changes (drafted in PR #9, closed unmerged). The owner questioned that route on 2026-10-16 (ADR corrections thread, 07:56 UTC): a near-copy record for every slip, and another for a slip in the copy, could work badly for records that are revised often.

This record decides how an error in an accepted record is fixed, and where the record of each fix is kept.

## Decision Drivers

- **Follow published practice.** Research batch RB-0029 ([evidence](../research/0006-allow-corrections-to-accepted-records.md)) read 14 sources. None asks for a near-copy record to fix an error that leaves the decision the same. Supersede is described for a decision that is reversed or changed.
- **Only the owner accepts.** A correction must need the same approval as an acceptance.
- **Keep the history.** Anyone must be able to see what the record said when the owner accepted it.
- **Replaceable** (REQ-0011): easy to tighten back to strict immutability.

## Considered Options

1. **Correct in place, with one corrections log for all records.** A changed decision still gets a new record.
2. **Supersede only** (D-0001 as first written): every fix is a full new record.
3. **Separate errata list** (as IETF RFCs do): the record never changes, and errors are listed in a separate file.
4. **Living document:** edit accepted records freely, with date-stamped notes.

## Decision Outcome

Chosen option: **1**.

```mermaid
flowchart LR
  E[Error found in an accepted record] --> Q{Does the decision change?}
  Q -- yes, or unsure --> N[New record]
  Q -- no --> P[Correction PR:<br/>each change, before and after]
  P --> R[Reviewing agent:<br/>decision unchanged?]
  R -- no --> N
  R -- yes --> J{the owner approves<br/>PR number + head SHA}
  J -- no --> X[PR closed]
  J -- yes --> C[Record edited in place<br/>one line in CORRECTIONS.md]
  C --> V[Reviewing agent compares<br/>merged record with approved commit]
  C --> G[git keeps the accepted text]
```

*In words:* if the decision would change, or it's unclear, write a new record. Otherwise open a correction PR that lists each change with its before and after text. A reviewing agent first says whether each change leaves the decision unchanged; if not, it becomes a new record. The owner then approves the PR the same way he accepts a record. If he declines, the PR closes, and a new record follows only if he says the decision should change. Once approved, the record is edited in place so it reads as the current text, one line is added to the corrections log, and a reviewing agent compares the merged record with the approved commit. Git keeps the text as it was accepted.

### What counts as a correction

A correction fixes an error without changing what was decided:
- spelling, grammar or wording that doesn't change meaning;
- a broken link, path or file name;
- a wrong ID or cross-reference;
- two parts of the record that contradict each other, where the Decision Outcome shows which one was meant;
- a factual slip in the context or consequences that the decision does not rely on;
- adding an evidence file built under D-0016 rule 3, and its link from the record;
- updating an earlier record's text so it matches a later accepted record that changed part of it, where the later record keeps the reasons.

A changed fact that the decision relies on is a changed decision, even if the chosen option stays the same. Anything else is a changed decision too: a different chosen option, a changed rule, condition, scope or list that the record sets. That needs a new record.

### How a correction is made

1. Branch `docs/correct-d-nnnn-<short>`. PR title `docs: correct D-NNNN: <summary>`.
2. The PR body lists every change, quoting the text before and after, and says why it is a correction, not a changed decision. Where the text removed is the owner's words, the PR body names where it was and a commit that holds it, instead of copying it (D-0016 rule 7).
3. The record is edited in place so it reads as the current text, with no Corrections section and no inline old-value notes. The PR adds one line to [`CORRECTIONS.md`](CORRECTIONS.md): the date, the record, what changed and the PR.
4. Before the owner sees it, a reviewing agent says for each change whether it leaves the decision unchanged. Any change it can't confirm moves to a new record.
5. The owner approves in the project chat, naming the PR number and head SHA, as for an acceptance.
6. After approval, only the approved head SHA may be added to that line. A reviewing agent compares the merged record with the approved commit, as for an acceptance.
7. `date` and `accepted-evidence` never change; they still describe the acceptance. Another front-matter field changes only if a listed correction fixes it.

### Consequences

- Good: fixing a mistake is one small PR, not a near-copy record, so the index lists decisions, not versions of the same decision, and each record reads as the current truth.
- Good: closest to the UK GDS Way and joelparkerhenderson's ADR guidance, and to the Python PEP 1 rule that resolved PEPs are "no longer substantially modified".
- Good: the text the owner accepted is still in git at the approved commit, and `CORRECTIONS.md` says what changed and in which PR.
- Bad: goes against the strict "never edit" guidance from AWS, Azure Well-Architected and Fowler.
- Bad: "the decision did not change" is a judgment call. The guards are that the owner approves each correction, and that anything unsure is treated as a changed decision.
- Neutral: the 4-digit ID was not a reason for this record. Reading `D-NNNN` as at least four digits, D-10000 still works, as `printf "%04d"` already does (evidence, finding 4).

### Confirmation

- Every merged change to an accepted record's body has a matching line in `CORRECTIONS.md` with its PR and approved commit.
- A reviewing agent compares each correction PR's merged diff with its listed changes.
- Every correction PR has a reviewing agent's note, written before the owner's approval, on whether each change leaves the decision unchanged.

## Pros and Cons of the Options

### 2. Supersede only
- Good: the strictest form, used by AWS, Azure Well-Architected and Fowler.
- Bad: a full new record for every slip, as with the PR #9 draft, and the index fills with near-copies.

### 3. Separate errata list
- Good: the accepted text never changes.
- Bad: readers must check two places to read a record correctly, and no ADR source in RB-0029 does this. The log chosen here differs: the record itself is fixed, and the log only says what changed.
- Kept as the fallback if in-place corrections ever cause trust problems once agents have their own identities.

### 4. Living document
- Good: least work.
- Bad: a changed decision could slip in as an edit, which undermines "only the owner accepts".

## More Information

- **Evidence:** [../research/0006-allow-corrections-to-accepted-records.md](../research/0006-allow-corrections-to-accepted-records.md): batch RB-0029, 14 sources read, 21 of 21 quoted passages matched the fetched text.
- **Exit path:** to return to strict immutability, a new record replaces this one; `CORRECTIONS.md` stays as the history. To switch to an errata list, the log's lines move into one file per record.
