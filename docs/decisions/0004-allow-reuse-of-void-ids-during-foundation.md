---
id: D-0004
title: During Foundation, allow a void ID's number to be reused, with the owner's approval and a tombstone
status: accepted
date: 2026-10-13
decision-makers: [jon]
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
  check: the drafting agent read the message in the Rules table thread at 2026-10-13T06:18Z, and the quote matches exactly. It answers the agent's message in the same thread (06:17:02Z), which named PR #7 and head 85ce152 and asked for "accept" naming both. The message itself names neither, so it relies on that context, as D-0003's acceptance did. An independent check by a reviewing agent is still to do.
  merged: not yet; Jon merges PR #7, which carries this evidence commit on top of the approved commit
legacy-id: []
revisit-when: the Activation gate passes; an ID family is referenced from outside Jon's own repositories and project; or a reuse leaves a reference that a search missed
---

# During Foundation, allow a void ID's number to be reused, with the owner's approval and a tombstone

## Context and Problem Statement

D-0003 rule 6 says "Never reuse, never delete" for every registered ID family, including `SR` requirements.

On 2026-10-13 the requirements register had a row, REQ-0021, that was a usage limit for one agent product. It broke two of the register's own rules: REQ-0008 (no vendor names) and REQ-0011 (everything replaceable). Jon dropped it at 04:23 UTC, because the system requirements should not name agent harnesses or vendors.

A new requirement (shared vocabulary) was then added as REQ-0022. Jon asked for the number REQ-0021 back (Central Hub project, Rules table thread, 2026-10-13 06:09 UTC), because the dropped row should never have been a rule and keeping the gap sat badly with building everything to be replaced. The reuse was done as a one-time exception in Research commit `f63ae969`. This record decides whether that exception becomes a rule, and on what conditions.

## Decision Drivers

- **The reason for "never reuse":** a reference must never silently point at a different item.
- **Early stage:** IDs are referenced only inside Jon's own repositories and project, and the number of references can be measured by search.
- **Gaps from mistakes:** a gap left by an entry that was never valid is noise in a small register.
- **Replaceable** (REQ-0011): the rule should be easy to tighten again later.

## Considered Options

1. **Reuse void IDs during Foundation only, under conditions** (below).
2. **Never reuse** (D-0003 rule 6 as written): revert REQ-0021 to REQ-0022.
3. **Reuse any dropped ID** while early.

## Decision Outcome

Chosen option: **1**.

```mermaid
flowchart LR
  A[Entry dropped] --> B{Was it void?<br/>never valid in its family}
  B -- no: superseded or withdrawn --> N[Never reuse<br/>D-0003 rule 6]
  B -- yes --> C{Foundation stage?}
  C -- no --> N
  C -- yes --> D{Owner approves<br/>this reuse}
  D -- no --> N
  D -- yes --> E[Search every repo and the Library<br/>for the old ID]
  E --> F[Update or annotate live references;<br/>leave frozen records and chat archives]
  F --> G[Keep a tombstone:<br/>'Former ID void' in the register]
```

*In words:* a dropped entry's number may be reused only if all of these are true:
1. The entry was **void**: it never met its family's own rules. A superseded or withdrawn entry that was once valid is never reused.
2. The system is still in **Foundation**: the Activation gate has not passed.
3. The **owner approves** that specific reuse.
4. The reuse is **traced**. Before the reuse:
   - search every repository and the Library for the old ID;
   - update or annotate every live reference;
   - leave frozen records and chat archives as they are.
5. The register keeps a **tombstone**: an entry such as "Former REQ-0021 (void)" that gives the old meaning, the reason, and what now holds the number.

Everything else in D-0003 stays in force, and rule 6 still applies to every case these conditions don't cover.

### Consequences

- Good: a mistake doesn't leave a permanent gap while the system is small.
- Good: the tombstone and the search keep the reason for "never reuse" intact. Nobody following an old reference is misled without being told.
- Bad: this goes against published practice. ARK, McMurry, OBO, PEP and DOORS all say never reuse (D-0003's [evidence](../research/0003-use-registered-id-families-and-file-qualified-labels.md), finding 2). McMurry's rule covers identifiers "generated and publicly advertised" (McMurry et al., reference 4 there), and Foundation IDs are not public in that sense. That reading is inferred, not quoted from a source.
- Bad: one more condition for a reviewer to check.
- Neutral: REQ-0021 is the only reuse so far. Its search found 6 files that meant the old entry: the 3 Rules table review files, the inbox row, Research `CURRENT-STATE.md`, and the register's own Dropped entry. All 6 were updated or annotated. 3 frozen study files and 20 chat archives were left as records. Results reported to Jon in the Rules table thread, 2026-10-13 06:13 UTC.

### Confirmation

- A reviewing agent checks every reused ID for a tombstone in its register and for a recorded search.
- The requirements register check (Research `areas/documentation/research/requirements-register/check/`) catches a duplicate SR ID; it does not check reuse conditions.

## Pros and Cons of the Options

### 2. Never reuse
- Good: matches every source in the D-0003 research.
- Bad: keeps a gap made by an entry that should never have existed, against the owner's call.

### 3. Reuse any dropped ID while early
- Good: simplest.
- Bad: a superseded entry was once a real rule, and old references to it are meaningful. Reusing it would mislead them.

## More Information

- **Evidence:** no research batch of its own. It rests on D-0003's research: [../research/0003-use-registered-id-families-and-file-qualified-labels.md](../research/0003-use-registered-id-families-and-file-qualified-labels.md).
- **Exit path:** when the Activation gate passes, this exception ends and D-0003 rule 6 applies unchanged; no record needs editing. To end it sooner, a new record supersedes this one.
- **Relation to D-0003:** this record narrows D-0003 rule 6 and does not supersede D-0003. If the owner prefers a full supersession, a new record would need to restate D-0003 in whole, because D-0001 keeps accepted bodies unchanged.

## Corrections

- **2026-10-23** (requirement IDs respelled under D-0014): 10 requirement IDs renamed, `SR08` to `REQ-0008`, `SR11` to `REQ-0011`, `SR21` to `REQ-0021`, `SR22` to `REQ-0022`. Before: `SR08`; after: `REQ-0008`, and the same for each pair listed. Reason: D-0014 retires the `SR` spelling and its rule 5 renames live references in place; no decision changes. Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23).
- **2026-10-23** (owner's words and approvals recorded in neutral form under D-0016). Reason: D-0016 rules 5 to 7 and its "What happens to the existing records"; no decision changes. Where the text removed is the owner's words, this entry names where it was and a commit that holds it (edac9fe) instead of copying it (D-0016 rule 7).
  1. `accepted-evidence` rewritten once into D-0016 rule 6 fields with D-0006 step 7's fixed mapping, as amended by D-0016: `timestamp` to `approved-at`, `message-id` to `approval-ref`, `quote-check` to `check`; `approved-by: owner` and `approval-names` added; `quote` removed (its text is in `accepted-evidence.quote` at commit edac9fe).
  2. Context and Problem Statement, second paragraph: the quote of Jon's 04:23 UTC message (at commit edac9fe) replaced by a neutral summary. After: "Jon dropped it at 04:23 UTC, because the system requirements should not name agent harnesses or vendors."
  3. Context and Problem Statement, third paragraph: the quote of Jon's 06:09 UTC message (at commit edac9fe) replaced by a neutral summary. After: "Jon asked for the number REQ-0021 back (Central Hub project, Rules table thread, 2026-10-13 06:09 UTC), because the dropped row should never have been a rule and keeping the gap sat badly with building everything to be replaced."
  4. Consequences, first Bad bullet. Before: "(D-0003 research, R3-practice line 250)" and "(R3-practice line 92)". After: "(D-0003's [evidence](../research/0003-use-registered-id-families-and-file-qualified-labels.md), finding 2)" and "(McMurry et al., reference 4 there)". Reason: the old pointers are private.
  5. More Information: a first bullet added, "**Evidence:** no research batch of its own. It rests on D-0003's research: [../research/0003-use-registered-id-families-and-file-qualified-labels.md](../research/0003-use-registered-id-families-and-file-qualified-labels.md)." Reason: D-0016 rule 2.
  6. The 2026-10-23 requirement-ID entry above: its approval, which quoted the approval message (at commit edac9fe), rewritten as D-0016 rule 6 facts. After: "Approval: Jon, 2026-10-23T04:04:08Z, message cmsg_01X43rfNYp4H1dL1V2dkfkwNSXxbYGet6tcD4ggBBduwLF, naming PR #23 and head cabb14e; approved commit cabb14e45f92ae73b089de0ce0ffb191dc47feea (PR #23)." No value changes.
  7. The closing note on tidied quotes removed (D-0016 rule 5). Before: "_Jon's quoted words are shown with spelling and punctuation tidied; his exact wording is kept in the original chat records._" After: none.

  Approval: the owner, 2026-10-23T05:22:43Z (approval-ref cmsg_01X43rfNYp4H1dL1V2dkfkwNJe6kJE76z6YiJbQ9y7Tg3i), naming PR #29 and head 97fd304; approved commit 97fd304459b3976d441c419564b8e082d64a1a47. Check: the drafting agent read the message at 2026-10-23T05:22Z and confirmed it names that PR and head.
