---
id: D-0004
title: During Foundation, allow a void or folded ID's number to be reused, with the owner's approval and a tombstone
status: accepted
date: 2026-10-13
decision-makers: [owner]
proposed-by: drafting-agent
consulted: []
waits-on: [D-0003]
supersedes: []
superseded-by:
accepted-evidence:
  approved-by: owner
  approved-at: 2026-10-13T06:18:47Z
  approved-commit: 85ce152e6e105f4406473c5912be63d0e8f3f43b
  approval-ref: cmsg_01X43rfNYp4H1dL1V2dkfkwN5xYTaeoa5nfZNqfToJKrD7
  approval-names: "PR #7 and head 85ce152 by context; it answers the agent's message (06:17:02Z) that named both"
  check: the drafting agent read the message in the Rules table thread at 2026-10-13T06:18Z, and the recorded wording matched it exactly. It answers the agent's message in the same thread (06:17:02Z), which named PR #7 and head 85ce152 and asked for "accept" naming both. The message itself names neither, so it relies on that context, as D-0003's acceptance did. An independent check by a reviewing agent is still to do.
  merged: PR #7 merged at 2026-10-13T06:20Z as 1c78db7, with this evidence commit on top of the approved commit
revisit-when: the Activation gate passes; an ID family is referenced from outside the owner's own repositories and project; or a reuse leaves a reference that a search missed
---

# During Foundation, allow a void or folded ID's number to be reused, with the owner's approval and a tombstone

## Context and Problem Statement

D-0003 rule 6 says "Never reuse, never delete" for every registered ID family, including `REQ` requirements.

On 2026-10-13 the requirements register had a row that was a usage limit for one agent product. It broke two of the register's own rules: REQ-0008 (no vendor names) and REQ-0011 (everything replaceable). The owner dropped it at 04:23 UTC, because the system requirements should not name agent harnesses or vendors.

The owner then asked for the new shared-vocabulary requirement to take its number (Central Hub project, Rules table thread, 2026-10-13 06:09 UTC), because the dropped row should never have been a rule and keeping the gap sat badly with building everything to be replaced. This record decides when a void entry's number may be reused, and on what conditions.

On 2026-10-25 the owner asked that decision numbers have no gaps after D-0013, D-0017 and D-0021 were folded into other records (D-0006). The folded numbers had held accepted decisions, so the tombstone matters most there: an older reference to D-0013 means the folded runbook-steps record, and the tombstone line says so.

## Decision Drivers

- **The reason for "never reuse":** a reference must never silently point at a different item.
- **Early stage:** IDs are referenced only inside the owner's own repositories and project, and the number of references can be measured by search.
- **Gaps from mistakes:** a gap left by an entry that was never valid is noise in a small register.
- **Replaceable** (REQ-0011): the rule should be easy to tighten again later.

## Considered Options

1. **Reuse void IDs during Foundation only, under conditions** (below).
2. **Never reuse** (D-0003 rule 6 as written): the void number stays a gap.
3. **Reuse any dropped ID** while early.

## Decision Outcome

Chosen option: **1**.

```mermaid
flowchart LR
  A[Entry dropped] --> B{Void, or a folded<br/>decision number?}
  B -- no: superseded or withdrawn --> N[Never reuse<br/>D-0003 rule 6]
  B -- yes --> C{Foundation stage?}
  C -- no --> N
  C -- yes --> D{Owner approves<br/>this reuse}
  D -- no --> N
  D -- yes --> E[Search every repo and the Library<br/>for the number]
  E --> F[Update or annotate live references;<br/>leave frozen records and chat archives]
  F --> G[Keep a tombstone<br/>in the register]
```

*In words:* a dropped entry's number may be reused only if all of these are true:
1. The entry was **void** (it never met its family's own rules), or it is a **decision record folded into another record** (D-0006). A folded decision number is reused by the next new decision record, lowest free number first, so decision numbers have no gaps. A superseded or withdrawn entry that was once valid is never reused.
2. The system is still in **Foundation**: the Activation gate has not passed.
3. The **owner approves** that specific reuse. For folded decision numbers, the owner approved reuse on 2026-10-25 at 01:21 UTC, covering every folded number during Foundation.
4. The reuse is **traced**. Before the reuse:
   - search every repository and the Library for the number;
   - update or annotate every live reference;
   - leave frozen records and chat archives as they are.
5. The register keeps a **tombstone**: a line that gives the void or folded entry's meaning, the reason, and what now holds the number. The decisions index is generated, so for a decision number the tombstone is a line in the numbers list of [`CORRECTIONS.md`](CORRECTIONS.md).

Everything else in D-0003 stays in force, and rule 6 still applies to every case these conditions don't cover.

### Consequences

- Good: a mistake doesn't leave a permanent gap while the system is small.
- Good: the tombstone and the search keep the reason for "never reuse" intact. Nobody following an earlier reference is misled without being told.
- Bad: this goes against published practice. ARK, McMurry, OBO, PEP and DOORS all say never reuse (D-0003's [evidence](../research/0003-use-registered-id-families-and-file-qualified-labels.md), finding 2). McMurry's rule covers identifiers "generated and publicly advertised" (McMurry et al., reference 4 there), and Foundation IDs are not public in that sense. That reading is inferred, not quoted from a source.
- Bad: one more condition for a reviewer to check.
- Neutral: each reused number is listed in [`CORRECTIONS.md`](CORRECTIONS.md), with its search.

### Confirmation

- A reviewing agent checks every reused ID for a tombstone in its register and for a recorded search.
- The requirements register check (Research `areas/documentation/research/requirements-register/check/`) catches a duplicate REQ ID; it does not check reuse conditions.

## Pros and Cons of the Options

### 2. Never reuse
- Good: matches every source in the D-0003 research.
- Bad: keeps a gap made by an entry that should never have existed, against the owner's call.

### 3. Reuse any dropped ID while early
- Good: simplest.
- Bad: a superseded entry was once a real rule, and earlier references to it are meaningful. Reusing it would mislead them.

## More Information

- **Evidence:** no research batch of its own. It rests on D-0003's research: [../research/0003-use-registered-id-families-and-file-qualified-labels.md](../research/0003-use-registered-id-families-and-file-qualified-labels.md).
- **Exit path:** when the Activation gate passes, this exception ends and D-0003 rule 6 applies unchanged; no record needs editing. To end it sooner, a new record supersedes this one.
