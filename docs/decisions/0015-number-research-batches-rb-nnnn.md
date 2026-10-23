---
id: D-0015
title: Number research batches RB-NNNN in one batch register, and rename the old batch codes everywhere
status: superseded
date: 2026-10-23
decision-makers: [jon]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001, D-0006, D-0014]
supersedes: [D-0014]
superseded-by: D-0018
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-23T04:21:52Z
  approved-commit: 1cce2f860ae2552047d2ba2b0bc960b45792bfda
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwNNC2krzzxxNCskiWfAqbKzw
  approval-names: "PR #24 and head 1cce2f8, in the message itself"
  check: the drafting agent read the message in the "Requirements register and SR ids" thread at 2026-10-23T04:21Z, and the quote matches exactly. It names the PR and the head SHA itself. An independent check by a reviewing agent is still to do.
  merged: not yet; Jon merges PR #24, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: the Activation gate passes; the Research repo is retired and research moves somewhere with its own numbering; or a batch register check finds a duplicate number
---

# Number research batches RB-NNNN in one batch register, and rename the old batch codes everywhere

## Context and Problem Statement

A research batch is one piece of research with its own folder and SPEC.md, kept outside this repo (the Research repo and the project files). Batches are cited from this repo, from chats and from each other by a short code such as `R3`, `RR1` or `CKA1`.

Agents made those codes up one at a time. Research batch RB-0074 ([evidence](../research/0015-number-research-batches-rb-nnnn.md)) measured them on 2026-10-23:

- 75 folders carry a code, written in 9 different shapes (`R3`, `RR1`, `R11b`, `ROUT-1`, `ADR-C1`, `cncf-catalogue`, and others). Nothing defines how a code is made.
- 3 codes name two different batches each: `RR1`, `AT1` and `VN1`.
- Some codes look like other labels: `SR1` looks like the retired `SR` requirement IDs, and `K1` and `V1` already mean other things.

Under D-0014 rule 5, Jon may approve renaming an agent-made label during Foundation. On 2026-10-23 at 04:16 UTC Jon chose the option to use RB-0001 style on the question "Number research batches as RB-0001 style, renamed everywhere?" (message cmsg_01X43rfNYp4H1dL1V2dkfkwNQcYS9um5zKTC7zv6b3o1qM).

Adding a family changes the family registry, so under D-0014 rule 2 it needs a record that supersedes D-0014.

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

Chosen option: **1**, which Jon chose on 2026-10-23 at 04:16 UTC.

D-0014's rules all carry over. Rule 1 gains one registry row. They are restated here so this record stands alone once it supersedes D-0014.

### The rules

1. **Global IDs are only for things cited across files, repos and chats.** These are the registered families:

   | Family | Pattern | Example | Home register | Who numbers it |
   |---|---|---|---|---|
   | Decisions | `D-NNNN` | `D-0007` | central-hub `docs/decisions/` | Set by D-0001: the number is assigned when the PR opens |
   | Requirements | `REQ-NNNN` | `REQ-0022` | Research `coordinator/system/REQUIREMENTS.md` | The requirements register owner: the next number is assigned only after Jon says yes to the wording |
   | Standards | `STD-NNNN` | `STD-0001` | central-hub `docs/standards/` | The standards register owner: the number is assigned when the standard's PR opens |
   | Research batches | `RB-NNNN` | `RB-0074` | Research `areas/documentation/research/BATCHES.md` | The batch register owner: the number is assigned when the batch's SPEC.md is written |

   The `SR` family stays retired. A sources family is still left out.

2. **One family registry.** The table above is the family registry. A change to it is a new decision record that supersedes this one.
   - A new family is added only with Jon's approval.
   - A new prefix must have at least two characters and must not equal or start with an existing one, ignoring case. `RB-` passes this check against `D-`, `REQ-` and `STD-`.
3. **Number late, with one owner per family.** A draft has no number and is cited by its file path (`D-TBD`, `REQ-TBD`, `STD-TBD`, `RB-TBD`). Check that the number is unique before merging. Outside rule 5's Foundation exception, a number never changes after it is assigned.
4. **Everything else is a local label.** Outside its own file, write it with the file name: `DECISION-MAP#P1`. A bare one-letter label outside its own file is a mistake that reviewers flag.
5. **Old labels are not renamed, except during Foundation.**
   - Until the Activation gate passes, Jon may approve renaming an agent-made ID or label. The rename is then applied to every live file in central-hub, the Research repo and the project files, so the files read as if the new name had always been used. No inline "was SR11" notes.
   - One corrections log per rename holds every old-to-new pair, the date and Jon's approval. Git history keeps the rest.
   - Records of what was said are never changed: the chat archive, captured transcripts and git history keep the old names.
   - Accepted decision records are corrected in place under D-0006, because a rename does not change any decision. Each correction PR lists every change, and Jon approves it by PR number and head SHA.
   - After the Activation gate passes, the old rule returns: when an item gets a new ID, its record lists the old one in `legacy-id`.
6. **Never reuse, never delete.** A superseded or withdrawn item keeps its ID, its status and a link to whatever replaced it. D-0004's Foundation exception for void IDs still applies.
7. **Keep meaning out of the number.** The prefix names the family and nothing else. A batch that continues another says so in its SPEC.md ("follows RB-0006"), not in its number.

### The batch register

- One Markdown table, one row per batch: ID, folder, question, SPEC date, status. It lives in the Research repo beside the batch folders.
- A batch is numbered when its SPEC.md is written, because the SPEC is how a batch is registered. An idea with no SPEC has no number.
- The folder name stays the batch's readable name. Folders are not renamed by this record.
- A check fails when two rows share a number or a batch folder has no row.

### The batch rename

- The batches that exist on acceptance are numbered `RB-0001` onward in order of their SPEC date. Ties break by the first git commit of the SPEC.md. A SPEC with no date takes its first commit date.
- One batch copied under two folder names (`R1`, `DG1`) gets one number. Codes that are aliases or parts of another batch (`RM2`, `R2b`) map to that batch's number.
- Each of the three clashing codes (`RR1`, `AT1`, `VN1`) is renamed only after its citation is read in context to tell which batch it means. About 280 citations need that read. Every other code is renamed by script.
- The full old-to-new list goes in the corrections log, not in this record.

### Order of work after acceptance

1. Research: write the batch register and its check.
2. Research and project files: rename every live batch code, read the clashing ones in context, and prove it with a search count of 0 live old codes outside the kept records.
3. Project instructions: the agent drafts any changed text, Jon approves it, and the coordinator saves it.
4. central-hub: one correction PR for every old batch code in accepted records and the PRD, under rule 5 and D-0006.

### Consequences

- Good: every batch has one name in one shape, and the three clashes end.
- Good: a register shows every batch, its question and its status in one place.
- Bad: a one-time sweep, with about 280 citations read by hand.
- Bad: old chats and git history keep the old codes, so a reader of old chats needs the corrections log.
- Neutral: no batch's content, folder or findings change.

### Confirmation

- The batch register check passes: no duplicate number, no batch folder without a row.
- After the sweep, a search of every live file finds 0 old batch codes outside the kept records, and the count is recorded in the corrections log.
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
- On acceptance, D-0014's lifecycle fields change to `status: superseded` and `superseded-by: D-0015`, under D-0001.

## Corrections

- **2026-10-23** (owner's words and approvals recorded in neutral form under D-0016). Reason: D-0016 rules 5 to 7 and its "What happens to the existing records"; no decision changes. Where the text removed is the owner's words, this entry names where it was and a commit that holds it (7915625) instead of copying it (D-0016 rule 7).
  1. `accepted-evidence` rewritten once into D-0016 rule 6 fields with D-0006 step 7's fixed mapping, as amended by D-0016: `timestamp` to `approved-at`, `message-id` to `approval-ref`, `quote-check` to `check`; `approved-by: owner` and `approval-names` added; `quote` removed (its text is in `accepted-evidence.quote` at commit 7915625). No value changes.
  2. Context and Problem Statement, second paragraph. Before: "Research batch `research/batch-ids/` (project files; Research repo copy `areas/documentation/research/batch-ids/`) measured them on 2026-10-23:" After: "Research batch RB-0074 ([evidence](../research/0015-number-research-batches-rb-nnnn.md)) measured them on 2026-10-23:" Reason: the old pointer is private; links the evidence file (D-0016 rule 1 as amended by D-0017).
  3. Context and Problem Statement, third paragraph: the quoted decision-card option label Jon chose described instead. Before: Jon chose "Yes, RB-0001 style" on the question. After: Jon chose the option to use RB-0001 style on the question.
  4. Decision Drivers, third bullet. Before: "(batch-ids LEDGER rows 6 to 10)" After: "(RB-0074, evidence finding 4)" Reason: the old pointer is private.
  5. More Information, first bullet. Before: "Research (project files outside this repo): `research/batch-ids/` (INVENTORY.md, LEDGER.md, SYNTHESIS.md). Research repo copy: `areas/documentation/research/batch-ids/`." After: "**Evidence:** [../research/0015-number-research-batches-rb-nnnn.md](../research/0015-number-research-batches-rb-nnnn.md): batch RB-0074." Reason: the old pointers are private; links the evidence file (D-0016 rule 1 as amended by D-0017).
  6. A Corrections section added, holding this entry.

  Approval: to be added after approval (D-0006 step 6).
