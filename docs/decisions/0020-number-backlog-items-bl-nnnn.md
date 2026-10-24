---
id: D-0020
title: Number every backlog item BL-NNNN, including open decisions, and rename the old row labels everywhere
status: proposed
date: 2026-10-24
decision-makers: [jon]
proposed-by: drafting-agent
consulted: [reviewing-agent]
waits-on: [D-0001, D-0006, D-0016, D-0018]
supersedes: [D-0018]
superseded-by:
legacy-id: []
revisit-when: the Activation gate passes; the backlog moves into a task management system with its own keys; or the backlog gets a second owner
---

# Number every backlog item BL-NNNN, including open decisions, and rename the old row labels everywhere

## Context and Problem Statement

The owner's backlog is one table in the project files. It holds every item that is waiting, blocked, parked or done. Open decisions also sit in a decision map beside it, which keeps their options. Neither table has registered IDs:

- 49 decision-map rows use one capital letter plus a number, such as `D1`, `K1` and `S7`. An agent made this scheme on 2026-10-10.
- 110 backlog rows use one of three label styles. 25 reuse a decision-map label, 83 use a lowercase word label such as `k8s-access-4a`, and 2 use other uppercase labels.

Research batch RB-0077 (evidence: [../research/0020-number-backlog-items-bl-nnnn.md](../research/0020-number-backlog-items-bl-nnnn.md)) found:

- `D1`, an open question about repo layout, looks like `D-0001`, an accepted record. Other files use their own `D1`, `A2` or `K1` for different things.
- None of the seven letters could become a registered prefix, because a prefix needs at least two characters (D-0018 rule 2).
- 24 decision-map rows are not in the backlog, and 15 of them are still open. So the backlog is not yet the one place for open questions.
- Every tracker the batch read gives each item one key from one sequence, and keeps the topic in the title.

The owner asked for the reasoning to be weighed without the cost of renaming existing files, because the system is new. On that basis the batch recommended numbers over word labels. On 2026-10-24 at 01:57 UTC the owner chose `BL-0001` style on a decision card that also offered readable word labels, or keeping the letter codes.

Adding a family changes the family registry, so under D-0018 rule 2 it needs a record that supersedes D-0018.

## Decision Drivers

- **One shape for every cited ID:** `D-0007`, `REQ-0022`, `STD-0001`, `RB-0077`, `RM-0033`.
- **An ID that never has to change:** a word label stops fitting when an item's wording grows; a number does not.
- **No clashes without judgment:** numbers come from one sequence, so two threads cannot pick the same one.
- **Readable:** the title is always shown next to the number.
- **Replaceable** (REQ-0011): the backlog can move into a task management system later.

## Considered Options

1. **`BL-NNNN` for every backlog item, renamed everywhere.**
2. **Readable word labels for every row.** The letter-code rows get word labels like the other 83 rows, such as `repo-layout`. No new family is needed. But a word label changes when the item's wording changes, and two threads can choose the same word.
3. **Keep the letter codes.** `D1` and `D-0001` keep looking alike.

## Decision Outcome

Chosen option: **1**, which the owner chose on 2026-10-24 at 01:57 UTC.

D-0018's rules all carry over. Rule 1 gains one registry row, and rule 4's example changes because `DECISION-MAP#P1` will no longer exist. They are restated here so this record stands alone once it supersedes D-0018.

### The rules

1. **Global IDs are only for things cited across files, repos and chats.** These are the registered families:

   | Family | Pattern | Example | Home register | Who numbers it |
   |---|---|---|---|---|
   | Decisions | `D-NNNN` | `D-0007` | central-hub `docs/decisions/` | Set by D-0001: the number is assigned when the PR opens |
   | Requirements | `REQ-NNNN` | `REQ-0022` | Research `coordinator/system/REQUIREMENTS.md` | The requirements register owner: the next number is assigned only after the owner says yes to the wording |
   | Standards | `STD-NNNN` | `STD-0001` | central-hub `docs/standards/` | The standards register owner: the number is assigned when the standard's PR opens |
   | Research batches | `RB-NNNN` | `RB-0077` | Research `areas/documentation/research/BATCHES.md` | The batch register owner: the number is assigned when the batch's SPEC.md is written |
   | Research methods | `RM-NNNN` | `RM-0033` | Research `areas/research-tooling/research/research-methods-crawl/methods/inventory.json` | The methods catalogue owner: the number is stored with the method and assigned only after the owner says yes to adding it, never from its place in the list |
   | Backlog items | `BL-NNNN` | `BL-0012` | project files `backlog/BACKLOG.md` | The backlog owner: the number is assigned when the row is added |

   The `SR` family stays retired. A sources family is still left out.

2. **One family registry.** The table above is the family registry. A change to it is a new decision record that supersedes this one.
   - A new family is added only with the owner's approval.
   - A new prefix must have at least two characters and must not equal or start with an existing one, ignoring case. `BL-` passes this check against `D-`, `REQ-`, `STD-`, `RB-` and `RM-`.
3. **Number late, with one owner per family.** A draft has no number and is cited by its file path (`D-TBD`, `REQ-TBD`, `STD-TBD`, `RB-TBD`, `RM-TBD`, `BL-TBD`). Check that the number is unique before merging. Outside rule 5's Foundation exception, a number never changes after it is assigned.
4. **Everything else is a local label.** Outside its own file, write it with the file name: `LIVE-PARAMETERS#S1`. A bare one-letter label outside its own file is a mistake that reviewers flag.
5. **Old labels are not renamed, except during Foundation.**
   - Until the Activation gate passes, the owner may approve renaming an agent-made ID or label. The rename is then applied to every live file in central-hub, the Research repo and the project files, so the files read as if the new name had always been used. No inline "was D1" notes.
   - One corrections log per rename holds every old-to-new pair, the date and the owner's approval. Git history keeps the rest.
   - Records of what was said are never changed: the chat archive, captured transcripts and git history keep the old names.
   - Accepted decision records are corrected in place under D-0006, because a rename does not change any decision. Each correction PR lists every change, and the owner approves it by PR number and head SHA.
   - After the Activation gate passes, the old rule returns: when an item gets a new ID, its record lists the old one in `legacy-id`.
6. **Never reuse, never delete.** A superseded or withdrawn item keeps its ID, its status and a link to whatever replaced it. A retired method stays in the catalogue, marked `deprecated` or `replaced by RM-NNNN`. A done backlog item keeps its number and its row. D-0004's Foundation exception for void IDs still applies.
7. **Keep meaning out of the number.** The prefix names the family and nothing else. A batch that continues another says so in its SPEC.md ("follows RB-0006"), not in its number. A backlog item's topic, status and owner stay in their columns, not in its number.

### The backlog numbers

- Every backlog row gets a `BL-NNNN` number, done rows included. Open decisions are backlog items, so they get one too.
- The decision map keeps its option tables, keyed by the same `BL-NNNN` numbers. The backlog is the one list. The map is where an open decision's options are written down.
- Every decision-map row becomes a backlog row first. The 15 open rows that are missing are added with their status, and the 9 decided or applied rows are added as done.
- First numbering: rows are numbered in the order of the table after those rows are added, starting at `BL-0001`. After that, each new row takes the next free number.
- In prose, the title goes next to the number: `BL-0012 (repo layout)`. Tables already have an Item column.
- When the owner decides an open question, the decision gets its own `D-NNNN`. The backlog row links to that record and is marked done.
- The table's check refuses a row label that is not `BL-NNNN`, and it refuses a duplicate number.

### Exit path

If the backlog moves into a task management system, each item moves once and takes that system's key. A mapping table from `BL-NNNN` to the new key is kept, so old citations still lead somewhere. The `BL` family is then marked closed in the registry by a record that supersedes this one.

### Order of work after acceptance

1. Project files: the backlog owner adds the missing decision-map rows, numbers every row, and updates the table's check.
2. Research and project files: rename the old labels by script in the same step. That covers the letter codes, the word labels written as `BACKLOG.md:<label>`, and both maps drawn from the table. Prove it with a search count of 0 old labels outside the kept records.
3. central-hub: one correction PR. D-0001 and D-0002 cite decision-map labels in `legacy-id` and `revisit-when`, and D-0001's field contract gives `W1` and `S7` as examples of backlog IDs.
4. Project instructions, if they cite a row label: the agent drafts, the owner approves, and the coordinator saves.

### Consequences

- Good: every cited ID has one shape, and `D1` no longer looks like `D-0001`.
- Good: the backlog becomes the one list of open questions, with none missing.
- Good: moving to a task system later is a one-to-one swap.
- Bad: numbers say less than words, so the title has to travel with them.
- Bad: about 110 labels and their citations are renamed, and the maps drawn from the table are rebuilt.
- Neutral: `BL` could also be read as "baseline". The registry and the title next to the number settle which is meant.

### Confirmation

- The backlog check passes: every row label is `BL-NNNN`, and there are no duplicates.
- Every decision-map row has a backlog row.
- After the rename, a search finds 0 old row labels outside the kept records and correction logs, and the count goes in the corrections log.

## Pros and Cons of the Options

### 1. BL-NNNN for every backlog item
- Good: one shape for every ID, stable, and no clashes.
- Bad: numbers are less readable than words without the title beside them.

### 2. Readable word labels
- Good: readable on their own, and no registry change.
- Bad: a label goes stale when an item's wording changes, and two threads can pick the same word.

### 3. Keep the letter codes
- Good: no work.
- Bad: `D1` and `D-0001` keep looking alike, and three label styles stay in one table.

## More Information

- **Evidence:** [../research/0020-number-backlog-items-bl-nnnn.md](../research/0020-number-backlog-items-bl-nnnn.md)
- Earlier renames handled the same way: requirement IDs (D-0014), research batch codes (D-0015) and research method IDs (D-0018).
- Related records: D-0001, D-0003, D-0006, D-0016, D-0017, D-0018.
- On acceptance, D-0018's lifecycle fields change to `status: superseded` and `superseded-by: D-0020`, under D-0001.
