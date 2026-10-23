---
id: D-0013
title: Give every runbook step a short why and ※ links back, and mark each runbook manual or automated
status: accepted
date: 2026-10-23
decision-makers: [jon]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0001, D-0012]
supersedes: []
superseded-by:
amends: [D-0012]
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-23T03:42:38Z
  approved-commit: eb33bd7b0ceba8560d683b9ff4620fe2a6aa8886
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNWc7Mzu6ZFvoYgnxsDKVyKh
  approval-names: "PR #21 and head eb33bd7, in the message itself"
  check: the drafting agent read the message in the documentation path thread at 2026-10-23T03:42Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; Jon merges PR #21, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: why lines grow into paragraphs; ※ links break often enough to need a link check; or every manual runbook has an automated twin and the manual ones stop being run
---

# Give every runbook step a short why and ※ links back, and mark each runbook manual or automated

## Context and Problem Statement

D-0012 sets the runbook template: a fixed header, then steps that each have an `expect:` line. It says nothing about why a step is done, or how steps connect.

On 2026-10-19 at 02:43 UTC Jon asked whether the cluster runbook explains why each step is done: not at length, but enough to understand the reasons and how the steps connect. Jon wanted it to read like a story, with asterisk reminders that link back to other parts. In the same message Jon asked for a manual runbook first, and an automated runbook using infrastructure and configuration as code later, because starting with the abstractions would hide what they are worth.

That request came before D-0012, and D-0012 missed it. This record adds it to the template.

## Decision Drivers

- **Jon understands every piece** (PRD goal 3). A step he can follow but not explain teaches nothing.
- **Short.** The why is a line, not an essay.
- **Manual first.** A hand-run runbook shows what the automation later saves.

## Considered Options

1. **A `why:` line per step, ※ links back, and a `kind` field** (this record).
2. **A why section at the top of each runbook**, with no per-step whys.
3. **No change.** Whys live in the decision records the runbook links to.

## Decision Outcome

Chosen option: **1**. Jon accepted this record under D-0001 on 2026-10-23 at 03:42 UTC.

### Rules

1. **Why per step.** Each step in `## Steps` has a `why:` line of one or two sentences, between the action and `expect:`.
2. **※ links back.** When a step relies on something explained in an earlier step or another document, it carries a `※` reminder that links there, for example `※ the pod network range was set in step 3`. A ※ link points to a step anchor or a document, never to a line number.
3. **Reads like a story.** The steps run in the order the work happens, and each why says how the step connects to the one before.
4. **Manual or automated.** The front matter gains `kind: manual | automated`. A `manual` runbook does each step by hand, and its scope is what the CKA exam tests. An `automated` runbook runs the same job through code in this repo, and links the `manual` runbook it replaces in `related`.
5. **Manual first.** For any job, the `manual` runbook is written and `tested` before its `automated` runbook is written.

The step part of D-0012's template becomes:

```markdown
## Steps
1. <one action: the exact command, or a link to the script>
   why: <one or two sentences: why this step, and how it connects to the last one>
   ※ <optional: what this relies on, linked to where it is explained>
   expect: <what you should see>
```

The front matter gains one line after `status`:

```markdown
kind: manual             # manual | automated
```

Everything else in D-0012 stays as it is.

### Consequences

- Good: a runbook teaches as well as instructs, which fits how Jon learns.
- Good: the `kind` field shows which jobs are still manual.
- Bad: runbooks get longer, and why lines can go stale when steps change. A step edit already resets `tested` to `draft` (D-0012), so whys are re-read at the next replay.
- Neutral: no runbook exists yet, so nothing has to be rewritten.

### Confirmation

- A reviewing agent checks each runbook PR for a `why:` line on every step and a `kind` value.
- An `automated` runbook links a `tested` `manual` runbook.

## Pros and Cons of the Options

### 2. One why section at the top
- Good: shorter.
- Bad: the reader has to hold the reasons in mind and match them to steps, which is what Jon asked to avoid.

### 3. No change
- Good: nothing to add.
- Bad: it misses Jon's 2026-10-19 request.

## More Information

- **Evidence:** no research batch. It rests on the owner's request described in the context.
- Related records: D-0012 (runbook format), D-0001.
- The cluster build runbook drafts in the Research repo (`RUNBOOK-v3-CKA.md`) already use this style. They are the first that will move under it.

## Corrections

- **2026-10-23** (owner's words and approvals recorded in neutral form under D-0016). Reason: D-0016 rules 5 to 7 and its "What happens to the existing records"; no decision changes. Where the text removed is the owner's words, this entry names where it was and a commit that holds it (7915625) instead of copying it (D-0016 rule 7).
  1. `accepted-evidence` rewritten once into D-0016 rule 6 fields with D-0006 step 7's fixed mapping, as amended by D-0016: `timestamp` to `approved-at`, `message-id` to `approval-ref`, `quote-check` to `check`; `approved-by: owner` and `approval-names` added; `quote` removed (its text is in `accepted-evidence.quote` at commit 7915625). No value changes.
  2. Context and Problem Statement, second paragraph: the two quotes of Jon's 02:43 UTC message (at commit 7915625) replaced by a neutral summary. After: "On 2026-10-19 at 02:43 UTC Jon asked whether the cluster runbook explains why each step is done: not at length, but enough to understand the reasons and how the steps connect. Jon wanted it to read like a story, with asterisk reminders that link back to other parts. In the same message Jon asked for a manual runbook first, and an automated runbook using infrastructure and configuration as code later, because starting with the abstractions would hide what they are worth."
  3. More Information: a first bullet added, "**Evidence:** no research batch. It rests on the owner's request described in the context." Reason: D-0016 rule 2.
  4. A Corrections section added, holding this entry.

  Approval: to be added after approval (D-0006 step 6).
